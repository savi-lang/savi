require "./pass/analyze"

##
# The purpose of the PreInfer pass is to build a topology of Infer::Info objects
# so that the later Infer pass can use these to infer/resolve types.
# While the Infer pass operates on reified functions and reified types
# (taking type parameters and other type context into account), this pass is
# restricted to building out info outside of any broader type context,
# allowing the info to be reused for different reifications of the same func.
# This pass also has a handful of compile errors that might be raised if there
# are problems with the function that prevent building out the topology.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the per-function level.
# This pass produces output state at the per-function level.
#
module Mare::Compiler::PreInfer
  struct Analysis
    getter yield_out_infos : Array(Infer::Local)
    property! yield_in_info : Infer::Local

    def initialize
      @yield_out_infos = [] of Infer::Local
      @redirects = {} of AST::Node => AST::Node
      @infos = {} of AST::Node => Infer::Info
    end

    protected def redirect(from : AST::Node, to : AST::Node)
      return if from == to # TODO: raise an error?

      @redirects[from] = to
    end

    def follow_redirects(node : AST::Node) : AST::Node
      while @redirects[node]?
        node = @redirects[node]
      end

      node
    end

    def [](node : AST::Node); @infos[follow_redirects(node)]; end
    def []?(node : AST::Node); @infos[follow_redirects(node)]?; end
    protected def []=(node, info); @infos[follow_redirects(node)] = info; end
  end

  class FuncVisitor < Mare::AST::Visitor
    getter analysis
    private getter func
    private getter link

    def initialize(
      @func : Program::Function,
      @link : Program::Function::Link,
      @analysis : Analysis,
      @inventory : Inventory::Analysis,
      @jumps : Jumps::Analysis,
      @classify : Classify::Analysis,
      @refer : Refer::Analysis,
    )
      @local_idents = Hash(Refer::Local, AST::Node).new
      @local_ident_overrides = Hash(AST::Node, AST::Node).new
      @redirects = Hash(AST::Node, AST::Node).new
    end

    def [](node : AST::Node)
      @analysis[node]
    end

    def []?(node : AST::Node)
      @analysis[node]?
    end

    def link
      @link
    end

    def params
      func.params.try(&.terms) || ([] of AST::Node)
    end

    def ret
      # The ident is used as a fake local variable that represents the return.
      func.ident
    end

    def run(ctx)
      # Complain if neither return type nor function body were specified.
      unless func.ret || func.body
        Error.at func.ident, \
          "This function's return type is totally unconstrained"
      end

      # Visit the function parameters, noting any declared types there.
      # We may need to apply some parameter-specific finishing touches.
      func.params.try do |params|
        params.accept(ctx, self)
        params.terms.each do |param|
          param_info = self[param]
          finish_param(param, param_info) unless param_info.is_a?(Infer::Param) \
            || (param_info.is_a?(Infer::FromAssign) && param_info.lhs.is_a?(Infer::Param))

          # TODO: special-case this somewhere else?
          if link.type.name == "Main" \
          && link.name == "new"
            env = Infer::FixedPrelude.new(func.ident.pos, "Env")
            param_info = self[param].as(Infer::Param)
            param_info.set_explicit(env) unless param_info.explicit?
          end
        end
      end

      # Create a fake local variable that represents the return value.
      # See also the #ret method.
      @analysis[ret] = Infer::FuncBody.new(ret.pos)

      # Take note of the return type constraint if given.
      # For constructors, this is the self type and listed receiver cap.
      if func.has_tag?(:constructor)
        self[ret].as(Infer::FuncBody).set_explicit(
          Infer::FromConstructor.new(func.cap.not_nil!.pos, func.cap.not_nil!.value)
        )
      else
        func.ret.try do |ret_t|
          ret_t.accept(ctx, self)
          self[ret].as(Infer::FuncBody).set_explicit(@analysis[ret_t])
        end
      end

      # Determine the number of "yield out" arguments, based on the maximum
      # number of arguments used in any yield statements here, as well as the
      # explicit yield_out part of the function signature if present.
      yield_out_arg_count = [
        (@inventory.each_yield.map(&.terms.size).to_a + [0]).max,
        func.yield_out.try do |yield_out|
          yield_out.is_a?(AST::Group) && yield_out.style == "(" \
          ? yield_out.terms.size : 0
        end || 0
      ].max

      # Create fake local variables that represents the yield-related types.
      yield_out_arg_count.times do
        @analysis.yield_out_infos << Infer::Local.new((func.yield_out || func.ident).pos)
      end
      @analysis.yield_in_info = Infer::Local.new((func.yield_in || func.ident).pos)

      # Constrain via the "yield out" part of the explicit signature if present.
      func.yield_out.try do |yield_out|
        if yield_out.is_a?(AST::Group) && yield_out.style == "(" \
        && yield_out.terms.size > 1
          # We have a function signature for multiple yield out arg types.
          yield_out.terms.each_with_index do |yield_out_arg, index|
            yield_out_arg.accept(ctx, self)
            @analysis.yield_out_infos[index].set_explicit(@analysis[yield_out_arg])
          end
        else
          # We have a function signature for just one yield out arg type.
          yield_out.accept(ctx, self)
          @analysis.yield_out_infos.first.set_explicit(@analysis[yield_out])
        end
      end

      # Constrain via the "yield in" part of the explicit signature if present.
      yield_in = func.yield_in
      if yield_in
        yield_in.accept(ctx, self)
        @analysis.yield_in_info.set_explicit(@analysis[yield_in])
      else
        fixed = Infer::FixedPrelude.new(@analysis.yield_in_info.pos, "None")
        @analysis.yield_in_info.set_explicit(fixed)
      end

      # Don't bother further typechecking functions that have no body
      # (such as FFI function declarations).
      func_body = func.body

      if func_body
        # Visit the function body, taking note of all observed constraints.
        func_body.accept(ctx, self)
        func_body_pos = func_body.terms.last.pos rescue func_body.pos

        # Assign the function body value to the fake return value local.
        # This has the effect of constraining it to any given explicit type,
        # and also of allowing inference if there is no explicit type.
        # We don't do this for constructors, since constructors implicitly return
        # self no matter what the last term of the body of the function is.
        self[ret].as(Infer::FuncBody).assign(ctx, @analysis[func_body], func_body_pos) \
          unless func.has_tag?(:constructor)
      end

      nil
    end

    def prelude_type(ctx : Context, name)
      ctx.namespace.prelude_type(name)
    end

    def reified_type(ctx : Context, *args)
      ctx.infer.for_rt(ctx, *args).reified
    end

    def reified_type_alias(ctx : Context, *args)
      ctx.infer.for_rt_alias(ctx, *args).reified
    end

    def lookup_local_ident(ref : Refer::Local)
      node = @local_idents[ref]?
      return unless node

      while @local_ident_overrides[node]?
        node = @local_ident_overrides[node]
      end

      node
    end

    def visit_children?(ctx, node)
      # Don't visit the children of a type expression root node.
      return false if @classify.type_expr?(node)

      # Don't visit children of a dot relation eagerly - wait for touch.
      return false if node.is_a?(AST::Relate) && node.op.value == "."

      # Don't visit children of Choices eagerly - wait for touch.
      return false if node.is_a?(AST::Choice)

      true
    end

    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(ctx, node)
      if @classify.type_expr?(node)
        # For type expressions, don't do the usual touch - construct info here.
        @analysis[node] = Infer::FixedTypeExpr.new(node.pos, node)
      else
        touch(ctx, node)
      end

      raise "didn't assign info to: #{node.inspect}" \
        if @classify.value_needed?(node) && self[node]? == nil

      node
    end

    def touch(ctx : Context, node : AST::Identifier)
      ref = @refer[node]
      case ref
      when Refer::Type
        if ref.with_value
          # We allow it to be resolved as if it were a type expression,
          # since this enum value literal will have the type of its referent.
          @analysis[node] = Infer::FixedEnumValue.new(node.pos, node)
        else
          # A type reference whose value is used and is not itself a value
          # must be marked non, rather than having the default cap for that type.
          # This is used when we pass a type around as if it were a value,
          # where that value is a stateless singleton able to call `:fun non`s.
          @analysis[node] = Infer::FixedSingleton.new(node.pos, node)
        end
      when Refer::TypeAlias
        @analysis[node] = Infer::FixedSingleton.new(node.pos, node)
      when Refer::TypeParam
        @analysis[node] = Infer::FixedSingleton.new(node.pos, node, ref)
      when Refer::Local
        # If it's a local, track the possibly new node in our @local_idents map.
        local_ident = lookup_local_ident(ref)
        if local_ident
          @analysis.redirect(node, local_ident)
        else
          @analysis[node] = ref.param_idx ? Infer::Param.new(node.pos) : Infer::Local.new(node.pos)
          @local_idents[ref] = node
        end
      when Refer::Self
        @analysis[node] = Infer::Self.new(node.pos)
      when Refer::RaiseError
        @analysis[node] = Infer::RaiseError.new(node.pos)
      when Refer::Unresolved
        # Leave the node as unresolved if this identifer is not a value.
        return if @classify.no_value?(node)

        # Otherwise, raise an error to the user:
        Error.at node, "This identifer couldn't be resolved"
      else
        raise NotImplementedError.new(ref)
      end
    end

    def touch(ctx : Context, node : AST::LiteralString)
      @analysis[node] = Infer::FixedPrelude.new(node.pos, "String")
    end

    # A literal character could be any integer or floating-point machine type.
    def touch(ctx : Context, node : AST::LiteralCharacter)
      defns = [prelude_type(ctx, "Numeric")]
      mts = defns.map { |defn| Infer::MetaType.new(reified_type(ctx, defn)).as(Infer::MetaType) } # TODO: is it possible to remove this superfluous "as"?
      mt = Infer::MetaType.new_union(mts).cap("val")
      @analysis[node] = Infer::Literal.new(node.pos, mt)
    end

    # A literal integer could be any integer or floating-point machine type.
    def touch(ctx : Context, node : AST::LiteralInteger)
      defns = [prelude_type(ctx, "Numeric")]
      mts = defns.map { |defn| Infer::MetaType.new(reified_type(ctx, defn)).as(Infer::MetaType) } # TODO: is it possible to remove this superfluous "as"?
      mt = Infer::MetaType.new_union(mts).cap("val")
      @analysis[node] = Infer::Literal.new(node.pos, mt)
    end

    # A literal float could be any floating-point machine type.
    def touch(ctx : Context, node : AST::LiteralFloat)
      defns = [prelude_type(ctx, "F32"), prelude_type(ctx, "F64")]
      mts = defns.map { |defn| Infer::MetaType.new(reified_type(ctx, defn)).as(Infer::MetaType) } # TODO: is it possible to remove this superfluous "as"?
      mt = Infer::MetaType.new_union(mts).cap("val")
      @analysis[node] = Infer::Literal.new(node.pos, mt)
    end

    def touch(ctx : Context, node : AST::Group)
      case node.style
      when "|"
        # Do nothing here - we'll handle it in one of the parent nodes.
      when "(", ":"
        @analysis[node] =
          Infer::Sequence.new(node.pos, node.terms.map { |term| self[term] })
      when "["
        @analysis[node] =
          Infer::ArrayLiteral.new(node.pos, node.terms.map { |term| self[term] })
      when " "
        ref = @refer[node.terms[0]]
        if ref.is_a?(Refer::Local) && ref.defn == node.terms[0]
          local_ident = @local_idents[ref]

          local = self[local_ident]
          case local
          when Infer::Local, Infer::Param
            info = self[node.terms[1]]
            case info
            when Infer::FixedTypeExpr, Infer::Self then local.set_explicit(info)
            else raise NotImplementedError.new(info)
            end
          else raise NotImplementedError.new(local)
          end

          @analysis.redirect(node, local_ident)
        else
          raise NotImplementedError.new(node.to_a)
        end
      else raise NotImplementedError.new(node.style)
      end
    end

    def touch(ctx : Context, node : AST::FieldRead)
      field = Infer::Field.new(node.pos, node.value) # TODO: consider caching this to reduce duplication?
      @analysis[node] = Infer::FieldRead.new(field, Infer::Self.new(field.pos))
    end

    def touch(ctx : Context, node : AST::FieldWrite)
      field = Infer::Field.new(node.pos, node.value) # TODO: consider caching this to reduce duplication?
      @analysis[node] = field
      field.assign(ctx, @analysis[node.rhs], node.rhs.pos)
    end

    def touch(ctx : Context, node : AST::FieldReplace)
      field = Infer::Field.new(node.pos, node.value) # TODO: consider caching this to reduce duplication?
      @analysis[node] = Infer::FieldExtract.new(field, Infer::Self.new(field.pos))
      field.assign(ctx, @analysis[node.rhs], node.rhs.pos)
    end

    def touch(ctx : Context, node : AST::Relate)
      case node.op.value
      when "->"
        # Do nothing here - we'll handle it in one of the parent nodes.
      when "=", "DEFAULTPARAM"
        lhs = self[node.lhs]
        case lhs
        when Infer::Local
          lhs.assign(ctx, @analysis[node.rhs], node.rhs.pos)
          @analysis[node] = Infer::FromAssign.new(node.pos, lhs, @analysis[node.rhs])
        when Infer::Param
          lhs.assign(ctx, @analysis[node.rhs], node.rhs.pos)
          @analysis[node] = Infer::FromAssign.new(node.pos, lhs, @analysis[node.rhs])
        else
          raise NotImplementedError.new(node.lhs)
        end
      when "."
        call_ident, call_args, yield_params, yield_block = AST::Extract.call(node)

        # Visit the left hand side of the call first, to get its info.
        # Note that we skipped it before with visit_children: false.
        node.lhs.try(&.accept(ctx, self))
        lhs_info = self[node.lhs]

        @analysis[node] = call = Infer::FromCall.new(
          call_ident.pos,
          lhs_info,
          call_ident.value,
          call_args,
          yield_params,
          yield_block,
          @classify.value_needed?(node),
        )

        @analysis[call_ident] = call

        # Each arg needs a link back to the FromCall with an arg index.
        call_args.try(&.accept(ctx, self))
        if call_args
          call_args.terms.each_with_index do |call_arg, index|
            new_info = Infer::TowardCallParam.new(call_arg.pos, call, index)
            @analysis[call_arg].add_downstream(call_arg.pos, new_info, 0)
            call.resolvables << new_info
          end
        end

        # Each yield param needs a link back to the FromCall with a param index.
        yield_params.try(&.accept(ctx, self))
        if yield_params
          yield_params.terms.each_with_index do |yield_param, index|
            new_info = Infer::FromCallYieldOut.new(yield_param.pos, call, index)
            @analysis[yield_param].as(Infer::Local).assign(ctx, new_info, yield_param.pos)
            call.resolvables << new_info
          end
        end

        # The yield block result info needs a link back to the FromCall as well.
        yield_block.try(&.accept(ctx, self))
        if yield_block
          new_info = Infer::TowardCallYieldIn.new(yield_block.pos, call)
          @analysis[yield_block].add_downstream(yield_block.pos, new_info, 0)
          call.resolvables << new_info
        end

      when "is"
        # Just know that the result of this expression is a boolean.
        @analysis[node] = new_info = Infer::FixedPrelude.new(node.pos, "Bool")
        new_info.resolvables << self[node.lhs]
        new_info.resolvables << self[node.rhs]
      when "<:"
        need_to_check_if_right_is_subtype_of_left = true
        lhs_info = self[node.lhs]
        rhs_info = self[node.rhs]
        Error.at node.rhs, "expected this to have a fixed type at compile time" \
          unless rhs_info.is_a?(Infer::FixedTypeExpr)

        # If the left-hand side is the name of a local variable...
        if lhs_info.is_a?(Infer::Local) || lhs_info.is_a?(Infer::Param)
          # Set up a local type refinement condition, which can be used within
          # a choice body to inform the type system about the type relationship.
          refine = @analysis.follow_redirects(node.lhs)
          @analysis[node] = Infer::TypeConditionForLocal.new(node.pos, refine, rhs_info)

        # If the left-hand side is the name of a type parameter...
        elsif lhs_info.is_a?(Infer::FixedSingleton) && lhs_info.type_param_ref
          # Strip the "non" from the fixed type, as if it were a type expr.
          @analysis[node.lhs] = new_lhs_info = Infer::FixedTypeExpr.new(node.lhs.pos, node.lhs)

          # Set up a type param refinement condition, which can be used within
          # a choice body to inform the type system about the type relationship.
          refine = lhs_info.type_param_ref.not_nil!
          @analysis[node] = Infer::TypeParamCondition.new(node.pos, refine, new_lhs_info, rhs_info)

        # If the left-hand side is the name of any other fixed type...
        elsif lhs_info.is_a?(Infer::FixedSingleton)
          # Strip the "non" from the fixed types, as if each were a type expr.
          @analysis[node.lhs] = lhs_info = Infer::FixedTypeExpr.new(node.lhs.pos, node.lhs)
          @analysis[node.rhs] = rhs_info = Infer::FixedTypeExpr.new(node.rhs.pos, node.rhs)

          # We can know statically at compile time whether it's true or false.
          @analysis[node] = Infer::TypeConditionStatic.new(node.pos, lhs_info, rhs_info)

        # For all other possible left-hand sides...
        else
          @analysis[node] = Infer::TypeCondition.new(node.pos, lhs_info, rhs_info)
        end

      else raise NotImplementedError.new(node.op.value)
      end
    end

    def touch(ctx : Context, node : AST::Qualify)
      raise NotImplementedError.new(node.group.style) \
        unless node.group.style == "("

      term_info = self[node.term]?

      # Ignore qualifications that are not type references. For example, this
      # ignores function call arguments, for which no further work is needed.
      # We only care about working with type arguments and type parameters now.
      return unless term_info.is_a?(Infer::FixedSingleton)

      @analysis[node] = Infer::FixedSingleton.new(node.pos, node, term_info.type_param_ref)
    end

    def touch(ctx : Context, node : AST::Prefix)
      case node.op.value
      when "source_code_position_of_argument"
        @analysis[node] = Infer::FixedPrelude.new(node.pos, "SourceCodePosition")
      when "reflection_of_type"
        @analysis[node] = Infer::ReflectionOfType.new(node.pos, @analysis[node.term])
      when "identity_digest_of"
        @analysis[node] = Infer::FixedPrelude.new(node.pos, "USize")
      when "--"
        @analysis[node] = Infer::Consume.new(node.pos, self[node.term])
      else
        raise NotImplementedError.new(node.op.value)
      end
    end

    def touch(ctx : Context, node : AST::Choice)
      branches = node.list.map do |cond, body|
        # Visit the cond AST - we skipped it before with visit_children: false.
        cond.accept(ctx, self)

        # Each condition in a choice must evaluate to a type of Bool.
        fixed_bool = Infer::FixedPrelude.new(node.pos, "Bool")
        cond_info = self[cond]
        cond_info.add_downstream(node.pos, fixed_bool, 1)

        inner_cond_info = cond_info
        while inner_cond_info.is_a?(Infer::Sequence)
          inner_cond_info = inner_cond_info.final_term
        end

        # If we have a type condition as the cond, that implies that it returned
        # true if we are in the body; hence we can apply the type refinement.
        # TODO: Do this in a less special-casey sort of way if possible.
        # TODO: Do we need to override things besides locals? should we skip for non-locals?
        if inner_cond_info.is_a?(Infer::TypeConditionForLocal)
          @local_ident_overrides[inner_cond_info.refine] = refine = inner_cond_info.refine.dup
          @analysis[refine] = Infer::Refinement.new(
            inner_cond_info.pos, self[inner_cond_info.refine], inner_cond_info.refine_type
          )
        end

        # Visit the body AST - we skipped it before with visit_children: false.
        body.accept(ctx, self)

        # Remove the override we put in place before, if any.
        if inner_cond_info.is_a?(Infer::TypeConditionForLocal)
          @local_ident_overrides.delete(inner_cond_info.refine).not_nil!
        end

        {cond ? self[cond] : nil, self[body], @jumps.away?(body)}
      end

      @analysis[node] = Infer::Phi.new(node.pos, branches)
    end

    def touch(ctx : Context, node : AST::Loop)
      # The condition of the loop must evaluate to a type of Bool.
      fixed_bool = Infer::FixedPrelude.new(node.pos, "Bool")
      cond_info = self[node.cond]
      cond_info.add_downstream(node.pos, fixed_bool, 1)

      @analysis[node] = Infer::Phi.new(node.pos, [
        {self[node.cond], self[node.body], @jumps.away?(node.body)},
        {nil, self[node.else_body], @jumps.away?(node.else_body)},
      ])
    end

    def touch(ctx : Context, node : AST::Try)
      @analysis[node] = Infer::Phi.new(node.pos, [
        {nil, self[node.body], @jumps.away?(node.body)},
        {nil, self[node.else_body], @jumps.away?(node.else_body)},
      ] of {Infer::Info?, Infer::Info, Bool})
    end

    def touch(ctx : Context, node : AST::Yield)
      raise "TODO: Nice error message for this" \
        if @analysis.yield_out_infos.size != node.terms.size

      term_infos =
        @analysis.yield_out_infos.zip(node.terms).map do |info, term|
          term_info = @analysis[term]
          info.assign(ctx, @analysis[term], term.pos)
          term_info
        end

      @analysis[node] = Infer::FromYield.new(node.pos, @analysis.yield_in_info, term_infos)
    end

    def touch(ctx : Context, node : AST::Node)
      # Do nothing for other nodes.
    end

    def finish_param(node : AST::Node, info : Infer::Info)
      case info
      when Infer::FixedTypeExpr
        param = Infer::Param.new(node.pos)
        param.set_explicit(info)
        @analysis[node] = param # assign new info
      else
        raise NotImplementedError.new([node, info].inspect)
      end
    end
  end

  class Pass < Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link)
      nil
    end

    def analyze_type(ctx, t, t_link)
      nil
    end

    def analyze_func(ctx, f, f_link, t_analysis)
      FuncVisitor.new(
        f,
        f_link,
        Analysis.new,
        ctx.inventory[f_link],
        ctx.jumps[f_link],
        ctx.classify[f_link],
        ctx.refer[f_link],
      ).tap(&.run(ctx)).analysis
    end
  end
end
