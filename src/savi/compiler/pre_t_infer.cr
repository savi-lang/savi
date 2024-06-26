require "./pass/analyze"

##
# The purpose of the PreTInfer pass is to build a topology of TInfer::Info objects
# so that the later TInfer pass can use these to infer/resolve types.
# While the TInfer pass operates on reified functions and reified types
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
module Savi::Compiler::PreTInfer
  struct Analysis
    getter yield_out_infos : Array(TInfer::YieldOut)
    property! yield_in_info : TInfer::YieldIn
    property! error_out_info : TInfer::ErrorOut

    def initialize
      @yield_out_infos = [] of TInfer::YieldOut
      @redirects = {} of AST::Node => AST::Node
      @infos = {} of AST::Node => TInfer::Info
      @extra_infos = [] of TInfer::Info
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
    protected def []=(node, info)
      @infos[follow_redirects(node)] = info
    end
    def each_info(&block : TInfer::Info -> Nil)
      @infos.each_value(&block)
      @extra_infos.each(&block)
    end
    protected def observe_extra_info(info)
      @extra_infos << info
    end
  end

  class FuncVisitor < Savi::AST::Visitor
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
      @type_context : TypeContext::Analysis,
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

    # Get the type context layer index of the given node.
    private def layer(node : AST::Node)
      @type_context.layer_index(node)
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
      func_ret = func.ret
      func_body = func.body

      # Complain if neither return type nor function body were specified.
      unless func_ret || func_body
        Error.at func.ident, \
          "This function's return type is totally unconstrained"
      end

      # Visit the function parameters, noting any declared types there.
      # We may need to apply some parameter-specific finishing touches.
      func.params.try do |params|
        params.accept(ctx, self)
        params.terms.each do |param|
          param_info = self[param]
          finish_param(param, param_info) unless param_info.is_a?(TInfer::Param) \
            || (param_info.is_a?(TInfer::FromAssign) && param_info.lhs.is_a?(TInfer::Param))

          # TODO: special-case this somewhere else?
          if link.type.name == "Main" \
          && link.name == "new"
            env = TInfer::FixedPrelude.new(func.ident.pos, 0, "Env")
            param_info = self[param].as(TInfer::Param)
            param_info.set_explicit(env) unless param_info.explicit?
          end
        end
      end

      # Create a fake local variable that represents the return value.
      # See also the #ret method.
      @analysis[ret] = TInfer::FuncBody.new(ret.pos, 0,
        @jumps.catches[ret]?.try(
          &.select(&.kind.is_a? AST::Jump::Kind::Return).map do |jump|
            inf = @analysis[jump]
            raise NotImplementedError.new("Jump should be of 'return' kind") \
              unless inf.is_a? TInfer::JumpReturn
            inf.as TInfer::JumpReturn
          end
        ) || [] of TInfer::JumpReturn,
      )

      # Take note of the return type constraint if given.
      # For constructors, this is the self type.
      if func.has_tag?(:constructor)
        self[ret].as(TInfer::FuncBody).set_explicit(
          TInfer::FromConstructor.new(func.cap.not_nil!.pos, 0)
        )
      elsif func_ret
        func_ret.accept(ctx, self)
        if !TInfer.is_type_expr_cap?(func_ret)
          self[ret].as(TInfer::FuncBody).set_explicit(@analysis[func_ret])
        end
      elsif func_body && @jumps.always_error?(func_body)
        none = TInfer::FixedPrelude.new(ret.pos, 0, "None")
        self[ret].as(TInfer::FuncBody).set_explicit(none)
      end

      # Determine the number of "yield out" arguments, based on the maximum
      # number of arguments used in any yield statements here, as well as the
      # explicit yield_out part of the function signature if present.
      yield_out_arg_count = [
        (@inventory.each_yield.map(&.terms.size).to_a + [0]).max,
        func.yield_out.try do |yield_out|
          yield_out.is_a?(AST::Group) && yield_out.style == "(" \
          ? yield_out.terms.size : 1
        end || 0
      ].max

      # Create fake local variables that represents the yield/error-related types.
      yield_out_arg_count.times do
        @analysis.yield_out_infos << TInfer::YieldOut.new((func.yield_out || func.ident).pos, 0)
      end
      @analysis.yield_in_info = TInfer::YieldIn.new((func.yield_in || func.ident).pos, 0)
      @analysis.error_out_info = TInfer::ErrorOut.new((func.error_out || func.ident).pos, 0)

      # Constrain via the "yield out" part of the explicit signature if present.
      func.yield_out.try do |yield_out|
        if yield_out.is_a?(AST::Group) && yield_out.style == "(" \
        && yield_out.terms.size > 1
          # We have a function signature for multiple yield out arg types.
          yield_out.terms.each_with_index do |yield_out_arg, index|
            yield_out_arg.accept(ctx, self)
            if !TInfer.is_type_expr_cap?(yield_out_arg)
              @analysis.yield_out_infos[index].set_explicit(@analysis[yield_out_arg])
            end
          end
        else
          # We have a function signature for just one yield out arg type.
          yield_out.accept(ctx, self)
          if !TInfer.is_type_expr_cap?(yield_out)
            @analysis.yield_out_infos.first.set_explicit(@analysis[yield_out])
          end
        end
      end

      # Constrain via the "yield in" part of the explicit signature if present.
      # Defaults to a fixed type of `None` if not in the explicit signature.
      yield_in = func.yield_in
      if yield_in
        yield_in.accept(ctx, self)
        if !TInfer.is_type_expr_cap?(yield_in)
          @analysis.yield_in_info.set_explicit(@analysis[yield_in])
        end
      else
        fixed = TInfer::FixedPrelude.new(@analysis.yield_in_info.pos, 0, "None")
        @analysis.yield_in_info.set_explicit(fixed)
      end

      # Constrain via the "error out" part of the explicit signature if present.
      error_out = func.error_out
      did_constrain_error_out = false
      if error_out
        error_out.accept(ctx, self)
        if !TInfer.is_type_expr_cap?(error_out)
          @analysis.error_out_info.set_explicit(@analysis[error_out])
        end
        did_constrain_error_out = true
      end

      # Don't bother further typechecking functions that have no body
      # (such as FFI function declarations).
      if func_body
        # Visit the function body, taking note of all observed constraints.
        func_body.accept(ctx, self)
        func_body_pos = func_body.terms.last.pos rescue func_body.pos

        # Assign the function body value to the fake return value local.
        # This has the effect of constraining it to any given explicit type,
        # and also of allowing inference if there is no explicit type.
        # We don't do this for constructors, since constructors implicitly return
        # self no matter what the last term of the body of the function is.
        unless func.has_tag?(:constructor) || @jumps.always_error?(func_body)
          self[ret].as(TInfer::FuncBody).assign(ctx, @analysis[func_body], func_body_pos)
          @jumps.catches[func.ast]?.try(&.each do |jump|
            next unless jump.kind == AST::Jump::Kind::Return
            self[ret].as(TInfer::FuncBody).assign(ctx, self[jump.term], jump.pos)
          end)
        end
      end

      # Constrain the "error out" part of the signature by any errors caught.
      @jumps.catches[func.ast]?.try(&.each { |jump|
        next unless jump.kind == AST::Jump::Kind::Error
        @analysis.error_out_info.assign(ctx, self[jump.term], jump.pos)
        did_constrain_error_out = true
      })
      @jumps.call_error_catches[func.ast]?.try(&.each { |call|
        call_error_info = TInfer::FromCallErrorOut.new(
          call.pos, self[call].layer_index, self[call].as(TInfer::FromCall)
        )
        @analysis.error_out_info.assign(ctx, call_error_info, call.pos)
        @analysis.observe_extra_info(call_error_info)
        did_constrain_error_out = true
      })

      # If the error out type is totally unconstrained, it's None.
      if !did_constrain_error_out
        fixed = TInfer::FixedPrelude.new(@analysis.error_out_info.pos, 0, "None")
        @analysis.error_out_info.set_explicit(fixed)
      end

      nil
    end

    def core_savi_mt(ctx : Context, name)
      t_link = ctx.namespace.core_savi_type(ctx, name)
      TInfer::MetaType.new(TInfer::ReifiedType.new(t_link))
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

      # Don't visit children of Calls eagerly - wait for touch.
      return false if node.is_a?(AST::Call)

      # Don't visit children of Choices eagerly - wait for touch.
      return false if node.is_a?(AST::Choice)

      true
    end

    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(ctx, node)
      if @classify.type_expr?(node)
        # For type expressions, don't do the usual touch - construct info here.
        @analysis[node] = TInfer::FixedTypeExpr.new(node.pos, layer(node), node)
      else
        touch(ctx, node)
      end

      raise "didn't assign info to: #{node.inspect}" \
        if @classify.value_needed?(node) && self[node]? == nil

      node
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end

    def touch(ctx : Context, node : AST::Identifier)
      ref = @refer[node]
      case ref
      when Refer::Type
        if ref.with_value
          @analysis[node] = TInfer::FixedEnumValue.new(node.pos, layer(node), node)
        else
          @analysis[node] = TInfer::FixedSingleton.new(node.pos, layer(node), node)
        end
      when Refer::TypeAlias
        @analysis[node] = TInfer::FixedSingleton.new(node.pos, layer(node), node)
      when Refer::TypeParam
        @analysis[node] = TInfer::FixedSingleton.new(node.pos, layer(node), node, ref)
      when Refer::Local
        local_ref = ref
        local_ident = lookup_local_ident(local_ref)
        if local_ident
          local_info = @analysis[local_ident].as(TInfer::DynamicInfo)
          @analysis[node] = TInfer::LocalRef.new(local_info, layer(node), local_ref)
        else
          @analysis[node] = local_ref.param_idx \
            ? TInfer::Param.new(node.pos, layer(node)) \
            : TInfer::Local.new(node.pos, layer(node))
          @local_idents[local_ref] = node
        end
      when Refer::Self
        @analysis[node] = TInfer::Self.new(node.pos, layer(node))
      when Refer::Unresolved
        # Leave the node as unresolved if this identifier is not a value.
        return if @classify.no_value?(node)
      else
        raise NotImplementedError.new(ref)
      end
    end

    def touch(ctx : Context, node : AST::Jump)
      term_info = @analysis[node.term.not_nil!]

      @analysis[node] = case node.kind
      when AST::Jump::Kind::Error
        TInfer::JumpError.new(node.pos, layer(node), term_info)
      when AST::Jump::Kind::Return
        TInfer::JumpReturn.new(node.pos, layer(node), term_info)
      when AST::Jump::Kind::Break
        TInfer::JumpBreak.new(node.pos, layer(node), term_info)
      when AST::Jump::Kind::Next
        TInfer::JumpNext.new(node.pos, layer(node), term_info)
      else
        raise ""
      end
    end

    def touch(ctx : Context, node : AST::LiteralString)
      @analysis[node] = (
        case node.prefix_ident.try(&.value)
        when nil then TInfer::FixedPrelude.new(node.pos, layer(node), "String")
        when "b" then TInfer::FixedPrelude.new(node.pos, layer(node), "Bytes")
        else
          ctx.error_at node.prefix_ident.not_nil!,
            "This type of string literal is not known; please remove this prefix"
          TInfer::FixedPrelude.new(node.pos, layer(node), "String")
        end
      )
    end

    # A literal character could be any integer or floating-point machine type.
    # If no type can be clearly inferred, we fall back to an I32 assumption.
    def touch(ctx : Context, node : AST::LiteralCharacter)
      possible = core_savi_mt(ctx, "Numeric.Convertible")
      fallback = core_savi_mt(ctx, "I32")
      @analysis[node] = TInfer::Literal.new(node.pos, layer(node), possible, fallback)
    end

    # A literal integer could be any integer or floating-point machine type.
    # If no type can be clearly inferred, we fall back to an I32 assumption.
    def touch(ctx : Context, node : AST::LiteralInteger)
      possible = core_savi_mt(ctx, "Numeric.Convertible")
      fallback = core_savi_mt(ctx, "I32")
      @analysis[node] = TInfer::Literal.new(node.pos, layer(node), possible, fallback)
    end

    # A literal float could be any floating-point machine type.
    # If no type can be clearly inferred, we fall back to an F64 assumption.
    def touch(ctx : Context, node : AST::LiteralFloat)
      # TODO: Allow inferring custom-declared floating-point types as well.
      possible = TInfer::MetaType.new_union([
        core_savi_mt(ctx, "F32"),
        core_savi_mt(ctx, "F64"),
      ])
      fallback = core_savi_mt(ctx, "F64")
      @analysis[node] = TInfer::Literal.new(node.pos, layer(node), possible, fallback)
    end

    def touch(ctx : Context, node : AST::Group)
      case node.style
      when "|"
        # Do nothing here - we'll handle it in one of the parent nodes.
      when "(", ":"
        @analysis[node] =
          TInfer::Sequence.new(node.pos, layer(node), node.terms.map { |term| self[term] })
      when "["
        @analysis[node] =
          TInfer::ArrayLiteral.new(node.pos, layer(node), node.terms.map { |term| self[term] })
      else raise NotImplementedError.new(node.style)
      end
    end

    def touch(ctx : Context, node : AST::FieldRead)
      field = TInfer::Field.new(node.pos, layer(node), node.value)
      @analysis[node] = TInfer::FieldRead.new(field, TInfer::Self.new(field.pos, layer(node)))
    end

    def touch(ctx : Context, node : AST::FieldWrite)
      field = TInfer::Field.new(node.pos, layer(node), node.value)
      @analysis[node] = field
      field.assign(ctx, @analysis[node.rhs], node.rhs.pos)
    end

    def touch(ctx : Context, node : AST::FieldDisplace)
      field = TInfer::Field.new(node.pos, layer(node), node.value)
      @analysis[node] = TInfer::FieldExtract.new(field, TInfer::Self.new(field.pos, layer(node)))
      field.assign(ctx, @analysis[node.rhs], node.rhs.pos)
    end

    def touch(ctx : Context, node : AST::Relate)
      case node.op.value
      when "->"
        # Do nothing here - we'll handle it in one of the parent nodes.
      when "EXPLICITTYPE"
        ref = @refer[node.lhs]?
        if ref.is_a?(Refer::Local)
          local_ident = @local_idents[ref]

          local = self[local_ident]
          case local
          when TInfer::Local, TInfer::Param
            info = self[node.rhs]
            if !TInfer.is_type_expr_cap?(node.rhs)
              case info
              when TInfer::FixedTypeExpr, TInfer::Self
                local.set_explicit(info)
              else raise NotImplementedError.new(info)
              end
            end
          else raise NotImplementedError.new(local)
          end

          @analysis.redirect(node, local_ident)
        else
          raise NotImplementedError.new(node.to_a)
        end
      when "=", "<<=", "DEFAULTPARAM"
        lhs = self[node.lhs]
        lhs = lhs.info if lhs.is_a?(TInfer::LocalRef)
        case lhs
        when TInfer::Local
          lhs.assign(ctx, @analysis[node.rhs], node.rhs.pos)
          @analysis[node] = TInfer::FromAssign.new(node.pos, layer(node), lhs, @analysis[node.rhs])
        when TInfer::Param
          lhs.assign(ctx, @analysis[node.rhs], node.rhs.pos)
          @analysis[node] = TInfer::FromAssign.new(node.pos, layer(node), lhs, @analysis[node.rhs])
        else
          raise NotImplementedError.new(lhs)
        end
      when "===", "!=="
        # Just know that the result of this expression is a boolean.
        @analysis[node] = new_info = TInfer::FixedPrelude.new(node.pos, layer(node), "Bool")
      when "<:", "!<:"
        positive_check = node.op.value == "<:"
        need_to_check_if_right_is_subtype_of_left = true
        lhs_info = self[node.lhs]
        rhs_info = self[node.rhs]
        Error.at node.rhs, "expected this to have a fixed type at compile time" \
          unless rhs_info.is_a?(TInfer::FixedTypeExpr)

        # If the left-hand side is the name of a local variable...
        if lhs_info.is_a?(TInfer::LocalRef) || lhs_info.is_a?(TInfer::Local) || lhs_info.is_a?(TInfer::Param)
          # Set up a local type refinement condition, which can be used within
          # a choice body to inform the type system about the type relationship.
          refine = @analysis.follow_redirects(node.lhs)
          @analysis[node] = TInfer::TypeConditionForLocal.new(node.pos, layer(node), refine, rhs_info, positive_check)

        # If the left-hand side is the name of a type parameter...
        elsif lhs_info.is_a?(TInfer::FixedSingleton) && lhs_info.type_param_ref
          # Strip the "non" from the fixed type, as if it were a type expr.
          @analysis[node.lhs] = new_lhs_info = TInfer::FixedTypeExpr.new(node.lhs.pos, layer(node), node.lhs)

          # Set up a type param refinement condition, which can be used within
          # a choice body to inform the type system about the type relationship.
          refine = lhs_info.type_param_ref.not_nil!
          @analysis[node] = TInfer::TypeParamCondition.new(node.pos, layer(node), refine, new_lhs_info, rhs_info, positive_check)

        # If the left-hand side is the name of any other fixed type...
        elsif lhs_info.is_a?(TInfer::FixedSingleton)
          # Strip the "non" from the fixed types, as if each were a type expr.
          @analysis[node.lhs] = lhs_info = TInfer::FixedTypeExpr.new(node.lhs.pos, layer(node.lhs), node.lhs)
          @analysis[node.rhs] = rhs_info = TInfer::FixedTypeExpr.new(node.rhs.pos, layer(node.rhs), node.rhs)

          # We can know statically at compile time whether it's true or false.
          @analysis[node] = TInfer::TypeConditionStatic.new(node.pos, layer(node), lhs_info, rhs_info, positive_check)

        # For all other possible left-hand sides...
        else
          @analysis[node] = TInfer::TypeCondition.new(node.pos, layer(node), lhs_info, rhs_info, positive_check)
        end

      when "static_address_of_function"
        @analysis[node] = TInfer::StaticAddressOfFunction.new(
          node.pos,
          layer(node),
          self[node.lhs],
          node.rhs.as(AST::Identifier).value
        )

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
      return unless term_info.is_a?(TInfer::FixedSingleton)

      @analysis[node] = TInfer::FixedSingleton.new(node.pos, layer(node), node, term_info.type_param_ref)
    end

    def touch(ctx : Context, node : AST::Prefix)
      case node.op.value
      when "source_code_position_of_argument"
        @analysis[node] = TInfer::FixedPrelude.new(node.pos, layer(node), "SourceCodePosition")
      when "stack_address_of_variable"
        @analysis[node] = TInfer::StackAddressOfVariable.new(node.pos, layer(node), @analysis[node.term])
      when "reflection_of_type"
        @analysis[node] = TInfer::ReflectionOfType.new(node.pos, layer(node), @analysis[node.term])
      when "reflection_of_runtime_type_name"
        @analysis[node] = info = TInfer::FixedPrelude.new(node.pos, layer(node), "String")
      when "identity_digest_of"
        @analysis[node] = info = TInfer::FixedPrelude.new(node.pos, layer(node), "USize")
      when "--"
        @analysis[node] = TInfer::Consume.new(node.pos, layer(node), @analysis[node.term])
      when "recover_UNSAFE"
        @analysis[node] = TInfer::RecoverUnsafe.new(node.pos, layer(node), @analysis[node.term])
      else
        raise NotImplementedError.new(node.op.value)
      end
    end

    def touch(ctx : Context, node : AST::Call)
      call_args = node.args
      yield_params = node.yield_params
      yield_block = node.yield_block

      # Visit the receiver of the call first, to get its info.
      # Note that we skipped it before with visit_children: false.
      node.receiver.accept(ctx, self)
      lhs_info = self[node.receiver]

      @analysis[node] = call = TInfer::FromCall.new(
        node.ident.pos,
        layer(node),
        lhs_info,
        node.ident.value,
        call_args,
        yield_params,
        yield_block,
        @classify.value_needed?(node),
      )

      @analysis[node.ident] = call

      # Each arg needs a link back to the FromCall with an arg index.
      if call_args
        call_args.accept(ctx, self)
        call_args.terms.each_with_index do |call_arg, index|
          new_info = TInfer::TowardCallParam.new(call_arg.pos, layer(node), call, index)
          @analysis[call_arg].add_downstream(call_arg.pos, new_info)
          @analysis.observe_extra_info(new_info)
        end
      end

      # Each yield param needs a link back to the FromCall with a param index.
      if yield_params
        yield_params.accept(ctx, self)
        yield_params.terms.each_with_index do |yield_param, index|
          new_info = TInfer::FromCallYieldOut.new(yield_param.pos, layer(node), call, index)
          @analysis[yield_param].as(TInfer::Local).assign(ctx, new_info, yield_param.pos)
          @analysis.observe_extra_info(new_info)
        end
      end

      # The yield block result info needs a link back to the FromCall as well.
      if yield_block
        yield_block.accept(ctx, self)
        new_info = TInfer::TowardCallYieldIn.new(yield_block.pos, layer(node), call)
        @analysis[yield_block].add_downstream(yield_block.pos, new_info)
        @analysis.observe_extra_info(new_info)

        # If there are next jumps caught by the yield block, they are observed
        # by the info node representing the "toward yield in" value.
        # If there are break jumps caught by the yield block, they are observed
        # by the info node representing the final call result.
        @jumps.catches[yield_block]?.try(&.each { |jump|
          jump_info = @analysis[jump]
          new_info.observe_next(jump_info) if jump_info.is_a?(TInfer::JumpNext)
          call.observe_break(jump_info) if jump_info.is_a?(TInfer::JumpBreak)
        })
      end
    end

    def touch(ctx : Context, node : AST::Choice)
      branches = node.list.map do |cond, body|
        # Visit the cond AST - we skipped it before with visit_children: false.
        cond.accept(ctx, self)
        cond_info = self[cond]

        inner_cond_info = cond_info
        while inner_cond_info.is_a?(TInfer::Sequence)
          inner_cond_info = inner_cond_info.final_term
        end

        # If we have a type condition as the cond, that implies that it returned
        # true if we are in the body; hence we can apply the type refinement.
        # TODO: Do this in a less special-casey sort of way if possible.
        # TODO: Do we need to override things besides locals? should we skip for non-locals?
        override_key = nil
        if inner_cond_info.is_a?(TInfer::TypeConditionForLocal)
          local_node = inner_cond_info.refine
          local_info = self[local_node]
          if local_info.is_a?(TInfer::LocalRef)
            local_node = lookup_local_ident(local_info.ref).not_nil!
            local_info = self[local_node]
          end

          override_key = local_node
          @local_ident_overrides[override_key] = refine = local_node.dup
          @analysis[refine] = TInfer::Refinement.new(
            inner_cond_info.pos,
            inner_cond_info.layer_index,
            local_info,
            inner_cond_info.refine_type,
            inner_cond_info.positive_check,
          )
        end

        # Visit the body AST - we skipped it before with visit_children: false.
        body.accept(ctx, self)

        # Remove the override we put in place before, if any.
        @local_ident_overrides.delete(override_key).not_nil! if override_key

        {cond ? self[cond] : nil, self[body], @jumps.away?(body)}
      end

      fixed_bool = TInfer::FixedPrelude.new(node.pos, layer(node), "Bool")
      @analysis.observe_extra_info(fixed_bool)

      @analysis[node] = choice = TInfer::Choice.new(node.pos, layer(node), branches, fixed_bool)
    end

    def touch(ctx : Context, node : AST::Loop)
      self[node.else_body].override_describe_kind =
        "loop's result when it runs zero times"

      fixed_bool = TInfer::FixedPrelude.new(node.pos, layer(node), "Bool")
      @analysis.observe_extra_info(fixed_bool)

      @analysis[node] = TInfer::Loop.new(node.pos, layer(node),
        [
          {self[node.initial_cond], self[node.body], @jumps.away?(node.body)},
          {nil, self[node.else_body], @jumps.away?(node.else_body)},
        ],
        fixed_bool,
        @jumps.catches[node]?.try(
          &.select(&.kind.is_a? AST::Jump::Kind::Break).map do |jump|
            inf = @analysis[jump]
            raise NotImplementedError.new("Jump should be of 'break' kind") \
              unless inf.is_a? TInfer::JumpBreak
            inf.as TInfer::JumpBreak
          end
        ) || [] of TInfer::JumpBreak,
        @jumps.catches[node]?.try(
          &.select(&.kind.is_a? AST::Jump::Kind::Next).map do |jump|
            inf = @analysis[jump]
            raise NotImplementedError.new("Jump should be of 'next' kind") \
              unless inf.is_a? TInfer::JumpNext
            inf.as TInfer::JumpNext
          end
        ) || [] of TInfer::JumpNext,
      )
    end

    def touch(ctx : Context, node : AST::Try)
      self[node.else_body].override_describe_kind =
        "try result when it catches an error"

      fixed_bool = TInfer::FixedPrelude.new(node.pos, layer(node), "Bool")
      @analysis.observe_extra_info(fixed_bool)

      @analysis[node] = choice = TInfer::Choice.new(node.pos, layer(node),
        [
          {nil, self[node.body], @jumps.away?(node.body)},
          {nil, self[node.else_body], @jumps.away?(node.else_body)},
        ] of {TInfer::Info?, TInfer::Info, Bool},
        fixed_bool
      )

      node.catch_expr.try { |catch_expr|
        catch_expr_info = self[catch_expr].as(TInfer::Local)
        catch_expr_info.set_infer_from_all_upstreams

        @jumps.catches[node]?.try(&.each { |jump|
          catch_expr_info.assign(ctx, self[jump.term], jump.pos)
        })

        @jumps.call_error_catches[node]?.try(&.each { |call|
          call_error_info = TInfer::FromCallErrorOut.new(
            call.pos, self[call].layer_index, self[call].as(TInfer::FromCall)
          )
          catch_expr_info.assign(ctx, call_error_info, call.pos)
          @analysis.observe_extra_info(call_error_info)
        })
      }
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

      @analysis[node] = TInfer::FromYield.new(node.pos, layer(node), @analysis.yield_in_info, term_infos)
    end

    def touch(ctx : Context, node : AST::Node)
      # Do nothing for other nodes.
    end

    def finish_param(node : AST::Node, info : TInfer::Info)
      case info
      when TInfer::FixedTypeExpr
        param = TInfer::Param.new(node.pos, layer(node))
        if !TInfer.is_type_expr_cap?(node)
          param.set_explicit(info)
        end
        @analysis[node] = param # assign new info
      else
        raise NotImplementedError.new([node, info].inspect)
      end
    end
  end

  class Pass < Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      inventory = ctx.inventory[f_link]
      jumps = ctx.jumps[f_link]
      classify = ctx.classify[f_link]
      refer = ctx.refer[f_link]
      type_context = ctx.type_context[f_link]
      deps = {inventory, jumps, classify, refer, type_context}
      prev = ctx.prev_ctx.try(&.pre_t_infer)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        FuncVisitor.new(f, f_link, Analysis.new, *deps).tap(&.run(ctx)).analysis
      end
    end
  end
end
