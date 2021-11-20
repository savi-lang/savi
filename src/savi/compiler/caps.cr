require "./pass/analyze"
require "./caps/**"

##
# WIP: This pass is intended to be a future replacement for the Infer pass,
# but it is still a work in progress and isn't in the main compile path yet.
#
module Savi::Compiler::Caps
  struct Analysis
    getter scope : CapVariable::Scope
    getter for_type : StructRef(Analysis)?

    getter! for_self : CapVariable
    getter! field_vars : Hash(String, CapVariable)
    getter! type_param_vars : Array(CapVariable)
    getter! receiver_var : CapVariable
    getter! param_vars : Array(CapVariable)
    getter! return_var : CapVariable

    def initialize(@scope, for_type : Analysis? = nil)
      @for_type = for_type ? StructRef(Analysis).new(for_type) : nil
      @sequence_number = 0

      @by_node = {} of AST::Node => CapSimple
      @local_vars_by_ref = {} of Refer::Info => CapVariable
      @vars = [] of CapVariable

      @var_lower_bounds = [] of Array({Source::Pos, CapSimple})
      @var_upper_bounds = [] of Array({Source::Pos, CapSimple})
    end

    def [](node : AST::Node); @by_node[node]; end
    def []?(node : AST::Node); @by_node[node]?; end

    protected def []=(node : AST::Node, t : CapSimple)
      @by_node[node] = t
    end

    def lower_bounds_of(var : CapVariable)
      case var.scope
      when @scope
        @var_lower_bounds[var.sequence_number - 1]
      when for_type.try(&.value.scope)
        for_type.not_nil!.value.lower_bounds_of(var)
      else
        raise NotImplementedError.new("can't reach properties of foreign vars")
      end
    end

    def upper_bounds_of(var : CapVariable)
      case var.scope
      when @scope
        @var_upper_bounds[var.sequence_number - 1]
      when for_type.try(&.value.scope)
        for_type.not_nil!.value.upper_bounds_of(var)
      else
        raise NotImplementedError.new("can't reach properties of foreign vars")
      end
    end

    protected def new_cap_var(nickname : String)
      CapVariable.new(nickname, @scope, @sequence_number += 1).tap { |var|
        @vars << var
        @var_lower_bounds << [] of {Source::Pos, CapSimple}
        @var_upper_bounds << [] of {Source::Pos, CapSimple}
      }
    end

    def show_cap_variables_list
      String.build { |output| show_cap_variables_list(output) }
    end
    def show_cap_variables_list(output : IO)
      for_type = @for_type
      if for_type
        for_type.show_cap_variables_list(output)
        output << "~~~\n"
      end

      @vars.each_with_index { |var, index|
        output << "\n" if index > 0
        show_cap_variable(output, var)
      }
    end

    def show_cap_variable(var : CapVariable)
      String.build { |output| show_cap_variable(output, var) }
    end
    def show_cap_variable(output, var : CapVariable)
      var.show(output)
      output << "\n"

      upper_bounds_of(var).each { |pos, sup|
        output << "  <: "
        sup.show(output)
        output << "\n"
        output << "  "
        output << pos.show.split("\n")[1..-1].join("\n  ")
        output << "\n"
      }
      lower_bounds_of(var).each { |pos, sub|
        output << "  :> "
        sub.show(output)
        output << "\n"
        output << "  "
        output << pos.show.split("\n")[1..-1].join("\n  ")
        output << "\n"
      }
    end

    protected def init_type_self(ctx, visitor : Visitor, params : AST::Group?)
      @type_param_vars = params.try(&.terms.map { |param|
        ident = AST::Extract.type_param(param).first
        var = new_cap_var(ident.value)
        raise NotImplementedError.new("type parameter cap inference")
        var
      })

      params.try(&.terms.each_with_index { |param, index|
        ident, explicit, default = AST::Extract.type_param(param)
        var = type_param_vars[index]

        explicit_cap = visitor.read_cap_expr(ctx, explicit) if explicit
        default_cap = visitor.read_cap_expr(ctx, default) if default

        @by_node[param] = var
        @by_node[ident] = var
        @by_node[explicit] = explicit_cap if explicit && explicit_cap
        @by_node[default] = default_cap if default && default_cap

        constrain(explicit.pos, var, explicit_cap.not_nil!) if explicit
      })
    end

    protected def init_type_fields(ctx, visitor : Visitor, fields : Array(Program::Function))
      # TODO: A CapVariable for each field.
      # @field_vars = fields.map { |f|
      #   {f.ident.value, new_cap_var(f.ident.value)}
      # }.to_h
    end

    protected def init_func_self(cap_node : AST::Identifier)
      @for_self = begin
        @receiver_var = var = new_cap_var("@")
        constrain(cap_node.pos, var, CapLiteral.from(cap_node.value))
        var
      end

      @param_vars = [] of CapVariable
    end

    protected def init_func_return_var(ctx, visitor : Visitor, f : Program::Function)
      @return_var = var = new_cap_var("return")

      ret = f.ret
      if ret
        explicit_cap = visitor.read_cap_expr(ctx, ret)
        if explicit_cap
          if f.body
            constrain(ret.pos, var, explicit_cap)
          else
            constrain_upper_and_lower(ret.pos, var, explicit_cap)
          end
        end
      end
    end

    protected def init_constructor_return_var(
      visitor : Visitor,
      pos : Source::Pos,
    )
      @return_var = @receiver_var
    end

    protected def observe_natural_return(node : AST::Group)
      constrain(node.terms.last.pos, @by_node[node], self.return_var)
    end

    protected def observe_early_return(node : AST::Jump)
      constrain(node.pos, @by_node[node.term], self.return_var)
    end

    protected def observe_yield(node : AST::Yield)
      raise NotImplementedError.new("yield in cap inference analysis")
      # vars = @yield_vars ||= [] of CapVariable
      # node.terms.each_with_index { |term, index|
      #   var = vars[index]? || begin
      #     v = new_cap_var("yield:#{index + 1}")
      #     vars << v
      #     v
      #   end
      #   constrain(node.pos, @by_node[term], var)
      # }

      # result_var = @yield_result_var ||= new_cap_var("yield:result")
      # @by_node[node] = result_var
    end

    protected def observe_constrained_literal_value(node, var_name, supertype)
      var = new_cap_var(var_name)
      constrain(node.pos, var, supertype)
      @by_node[node] = var
    end

    protected def observe_assert_bool(ctx, node)
      # Note that Bool conditions are always Bool'val
      constrain(node.pos, @by_node[node], CapLiteral.val)
    end

    protected def observe_self_reference(node, ref)
      @by_node[node] = for_self
    end

    protected def observe_local_reference(node, ref)
      var = @local_vars_by_ref[ref] ||= new_cap_var(ref.name)
      @by_node[node] = var
    end

    protected def observe_local_consume(node, ref)
      var = @local_vars_by_ref[ref] ||= new_cap_var(ref.name)
      @by_node[node] = var
    end

    protected def observe_assignment(node, ref)
      var = @local_vars_by_ref[ref]

      explicit = AST::Extract.param(node.lhs)[1]
      constrain_upper_and_lower(explicit.pos, var, @by_node[explicit]) if explicit

      rhs = @by_node[node.rhs]
      constrain(node.pos, rhs, var)

      @by_node[node] = var
    end

    protected def observe_param(node, ref)
      ident, explicit, default = AST::Extract.param(node)
      var = @local_vars_by_ref[ref]
      param_vars << var

      if explicit
        # Params differ from local variables in that their explicit type
        # creates a constraint rather than a fully-equivalent binding.
        constrain(explicit.pos, var, @by_node[explicit])
      end

      constrain(node.pos, @by_node[default], var) if default

      @by_node[node] = var
    end

    protected def observe_field_access(node)
      for_type = @for_type.not_nil!.value
      var = for_type.field_vars[node.value]
      case node
      when AST::FieldRead
        @by_node[node] = var
      when AST::FieldWrite
        @by_node[node] = var
        constrain(node.pos, @by_node[node.rhs], var)
      when AST::FieldDisplace
        @by_node[node] = var
        constrain(node.pos, @by_node[node.rhs], var)
      end
    end

    protected def observe_field_func(ctx, visitor, f : Program::Function)
      var = @for_type.not_nil!.field_vars[f.ident.value]

      f.ret.try { |ret|
        explicit_cap = visitor.read_cap_expr(ctx, ret)
        constrain_upper_and_lower(ret.pos, var, explicit_cap) if explicit_cap
      }
      f.body.try { |body|
        constrain(body.pos, @by_node[body], var)
      }
    end

    protected def observe_call(call : AST::Call)
      receiver_cap = @by_node[call.receiver]

      # TODO: Use receiver type to recurse to analyzing a different function -
      # the function or functions being called here, to get the caps
      # of their param vars and return vars.

      call.args.try(&.terms.each_with_index { |term, index|
        param_var = new_cap_var("#{call.ident.value}(#{index})")

        constrain(term.pos, @by_node[term], param_var)
      })

      result_var = new_cap_var(call.ident.value)

      @by_node[call] = result_var
    end

    protected def observe_array_literal(ctx, node)
      raise NotImplementedError.new("arrays in cap inference pass")

      # var = new_cap_var("array:group")
      # elem_var = new_cap_var("array:elem")

      # @by_node[node] = var

      # array_type = TypeNominal.new(
      #   ctx.namespace.prelude_type(ctx, "Array"),
      #   [elem_var.as(CapSimple)]
      # )
      # constrain(node.pos, var, array_type)

      # node.terms.each { |elem|
      #   constrain(node.pos, @by_node[elem], elem_var)
      # }
    end

    protected def constrain_upper_and_lower(
      pos : Source::Pos,
      var : CapVariable,
      explicit_cap : CapSimple,
    )
      # TODO: Can we bind more efficiently than this?
      constrain(pos, var, explicit_cap)
      constrain(pos, explicit_cap, var)
    end

    protected def constrain(
      pos : Source::Pos,
      sub : CapSimple,
      sup : CapSimple,
      seen_vars = Set({CapSimple, CapSimple}).new,
    )
      # If the types are identical, there is nothing to be done.
      return if sub == sup

      # If the subtype is the bottom type or the supertype is the top type,
      # then this constraint is a trivial fact needing no further examination.
      return if sub.is_a?(CapLiteral) && sub.bottom?
      return if sup.is_a?(CapLiteral) && sup.top?

      # Avoid doing duplicate work: if one side or the other is a type variable,
      # check the cache of already constrained type variables, and bail out
      # if we've already started constraining the given variable against the
      # given sub- or super-type it is being constrained with here.
      if sub.is_a?(CapVariable) || sup.is_a?(CapVariable)
        return if seen_vars.includes?({sub, sup})
        seen_vars.add({sub, sup})
      end

      if sub.is_a?(CapVariable) && sup.level <= sub.level
        # Otherwise, if the subtype is a type variable,
        # prefer putting constraints in the subtype,
        # as long as the subtype is at or above the "level" of the supertype.
        upper_bounds_of(sub) << {pos, sup}
        lower_bounds_of(sub).each { |b| constrain(b.first, b.last, sup, seen_vars) }
      elsif sup.is_a?(CapVariable) && sub.level <= sup.level
        # Otherwise, try putting constraints in the supertype,
        # as long as the supertype is at or above the "level" of the subtype.
        lower_bounds_of(sup) << {pos, sub}
        upper_bounds_of(sup).each { |b| constrain(b.first, sub, b.last, seen_vars) }
      elsif sub.is_a?(CapVariable)
        raise NotImplementedError.new("constrain sub variable across levels")
      elsif sup.is_a?(CapVariable)
        raise NotImplementedError.new("constrain sup variable across levels")
      else
        raise NotImplementedError.new("#{sub.show} <: #{sup.show}\n#{pos.show}")
      end
    end
  end

  class Visitor < AST::Visitor
    getter analysis
    private getter infer : Infer::Analysis
    private getter refer_type : ReferType::Analysis
    private getter! refer : Refer::Analysis
    private getter! classify : Classify::Analysis # only present within a func

    def initialize(
      @analysis : Analysis,
      @infer,
      @refer_type,
      @refer = nil,
      @classify = nil,
    )
    end

    def run_for_type_alias(ctx : Context, t : Program::TypeAlias)
      # TODO: Allow running this pass for more than just the root library.
      # We restrict this for now while we are building out the pass because
      # we don't want to deal with all of the complicated forms in the prelude.
      # We want to stick to the simple forms in the compiler pass specs for now.
      root_library = ctx.root_library.source_library
      return unless t.ident.pos.source.library == root_library

      raise NotImplementedError.new("run_for_type_alias")
    end

    def run_for_type(ctx : Context, t : Program::Type)
      # TODO: Allow running this pass for more than just the root library.
      # We restrict this for now while we are building out the pass because
      # we don't want to deal with all of the complicated forms in the prelude.
      # We want to stick to the simple forms in the compiler pass specs for now.
      root_library = ctx.root_library.source_library
      return unless t.ident.pos.source.library == root_library

      @analysis.init_type_self(ctx, self, t.params)
      @analysis.init_type_fields(ctx, self, t.functions.select(&.has_tag?(:field)))
    end

    def run_for_function(ctx : Context, f : Program::Function)
      # TODO: Allow running this pass for more than just the root library.
      # We restrict this for now while we are building out the pass because
      # we don't want to deal with all of the complicated forms in the prelude.
      # We want to stick to the simple forms in the compiler pass specs for now.
      root_library = ctx.root_library.source_library
      return unless f.ident.pos.source.library == root_library

      @analysis.init_func_self(f.cap)
      if f.has_tag?(:constructor)
        @analysis.init_constructor_return_var(self, f.ident.pos)
      else
        @analysis.init_func_return_var(ctx, self, f)
      end

      f.params.try(&.terms.each { |param| visit_param_deeply(ctx, param) })
      f.body.try(&.accept(ctx, self))

      unless f.has_tag?(:constructor)
        f.body.try { |body| @analysis.observe_natural_return(body) }
      end

      analysis.observe_field_func(ctx, self, f) if f.has_tag?(:field)
    end

    def visit_any?(ctx, node)
      # Read type expressions using a different, top-down kind of approach.
      # This prevents the normal depth-first visit when false is returned.
      if !@classify || classify.type_expr?(node)
        cap = read_cap_expr(ctx, node)
        @analysis[node] = cap if cap
        false
      else
        true
      end
    end

    def read_cap_expr(ctx, node : AST::Identifier)
      ref = @refer_type[node]?

      case ref
      when Refer::Self
        @analysis.for_self
      when Refer::Type
        # A nominal type tells us nothing about capabilities.
        nil
      when Refer::TypeParam
        analysis = @analysis
        while analysis.scope != ref.parent_link
          analysis = analysis.for_type.not_nil!.value
        end
        analysis.type_param_vars[ref.index]
      when nil
        cap = CapLiteral.from(node.value) rescue nil
        ctx.error_at node, "This type couldn't be resolved" unless cap
        cap
      else
        raise NotImplementedError.new(ref.class)
      end
    end

    def read_cap_expr(ctx, node : AST::Relate)
      case node.op.value
      when "->"
        raise NotImplementedError.new("viewpoints in cap inference pass")
      when "'"
        # Nominal types are ignored - just keep the right-hand-side.
        # TODO: Handle region names affixed to caps with this same operator.
        read_cap_expr(ctx, node.rhs)
      else
        raise NotImplementedError.new(node.op.value)
      end
    end

    def read_cap_expr(ctx, node : AST::Qualify)
      raise NotImplementedError.new(node.to_a) unless node.group.style == "("

      # We don't care about the application of type args to a nominal type.
      # We ignore nominal types in this pass, so we just return the term cap,
      # which should be nil because it is a nominal type we ignored.
      read_cap_expr(ctx, node.term)
    end

    def read_cap_expr(ctx, node : AST::Group)
      case node.style
      when "("
        raise NotImplementedError.new("multiple terms in type expr group") \
          unless node.terms.size == 1
        read_cap_expr(ctx, node.terms.first)
      when "|"
        raise NotImplementedError.new("explicit union types in cap inference pass")
        # CapUnion.from(node.terms.map { |term| read_cap_expr(ctx, term) })
      else
        raise NotImplementedError.new(node.style)
      end
    end

    def read_cap_expr(ctx, node)
      raise NotImplementedError.new(node.class)
    end

    def visit(ctx, node : AST::Identifier)
      return if classify.no_value?(node)

      ref = (@refer || @refer_type)[node]
      case ref
      when Refer::Self
        @analysis.observe_self_reference(node, ref)
      when Refer::Local
        @analysis.observe_local_reference(node, ref)
      when Refer::Type
        if ref.with_value
          # We allow it to be resolved as if it were a type expression,
          # since this enum value literal will have the type of its referent.
          # An enum value is always immutable, so we pin it to `val` here.
          @analysis[node] = CapLiteral.val
        else
          # A type whose value is used and is not itself a value is a `non`.
          # This is used when we pass a type around as if it were a value,
          # where that value is a stateless singleton able to call `:fun non`s.
          @analysis[node] = CapLiteral.non
        end
      when Refer::TypeParam
        analysis = @analysis
        while analysis.scope != ref.parent_link
          analysis = analysis.for_type.not_nil!.value
        end
        @analysis[node] = analysis.type_param_vars[ref.index]
      else
        raise NotImplementedError.new(ref.class)
      end
    end

    def visit(ctx, node : AST::LiteralCharacter)
      @analysis[node] = CapLiteral.val
    end

    def visit(ctx, node : AST::LiteralInteger)
      @analysis[node] = CapLiteral.val
    end

    def visit(ctx, node : AST::LiteralFloat)
      @analysis[node] = CapLiteral.val
    end

    def visit(ctx, node : AST::LiteralString)
      @analysis[node] = CapLiteral.val
    end

    def visit(ctx, node : AST::Group)
      case node.style
      when "|"
        # Do nothing here - we'll handle it in one of the parent nodes.
      when "["
        raise NotImplementedError.new("arrays in cap inference pass")
      when "(", ":"
        if node.terms.empty?
          # An empty expression sequence has a result value of None'non.
          @analysis[node] = CapLiteral.non
        else
          @analysis[node] = @analysis[node.terms.last]
        end
      else raise NotImplementedError.new(node.style)
      end
    end

    def visit(ctx, node : AST::Operator)
      # Do nothing.
    end

    def visit(ctx, node : AST::Prefix)
      case node.op.value
      when "source_code_position_of_argument",
           "reflection_of_type",
           "reflection_of_runtime_type_name",
           "identity_digest_of"
        # These special intrinsics all return an immutable value.
        @analysis[node] = CapLiteral.val
      when "--"
        raise NotImplementedError.new("consume in cap inference pass")
      else
        raise NotImplementedError.new(node.op.value)
      end
    end

    def visit(ctx, node : AST::Qualify)
      raise NotImplementedError.new(node.to_a) unless node.group.style == "("

      # A qualified type has the `non` cap, like all type expressions do
      # when they are used as a value expression.
      @analysis[node] = CapLiteral.non
    end

    def visit(ctx, node : AST::Relate)
      case node.op.value
      when "EXPLICITTYPE"
        # Do nothing here - we'll handle it in one of the parent nodes.
      when "<:", "!<:"
        raise NotImplementedError.new("flow typing in cap inference")
      when "===", "!=="
        # Just know that the result of this expression is a Bool'val.
        @analysis[node] = CapLiteral.val
      when "="
        ident = AST::Extract.param(node.lhs).first
        ref = refer[ident].as(Refer::Local)
        @analysis.observe_assignment(node, ref)
      else
        raise NotImplementedError.new(node.op.value)
      end
    end

    def visit_param_deeply(ctx, node)
      ident, explicit, default = AST::Extract.param(node)
      ref = refer[ident].as(Refer::Local)

      ident.accept(ctx, self)
      explicit.try(&.accept(ctx, self))
      default.try(&.accept(ctx, self))

      @analysis.observe_param(node, ref)
    end

    def visit(ctx, node : AST::Choice)
      node.list.each { |cond, body|
        @analysis.observe_assert_bool(ctx, cond)
      }
      @analysis[node] = var = @analysis.new_cap_var("choice:result")
      # TODO: Leverage the condition for flow typing.
      node.list.each { |cond, body|
        @analysis.constrain(body.pos, @analysis[body], var)
      }
    end

    def visit(ctx, node : AST::Loop)
      @analysis.observe_assert_bool(ctx, node.initial_cond)
      @analysis.observe_assert_bool(ctx, node.repeat_cond)
      @analysis[node] = var = @analysis.new_cap_var("loop:result")
      @analysis.constrain(node.body.pos, @analysis[node.body], var)
      @analysis.constrain(node.else_body.pos, @analysis[node.else_body], var)
    end

    def visit(ctx, node : AST::Try)
      @analysis[node] = var = @analysis.new_cap_var("try:result")
      @analysis.constrain(node.body.pos, @analysis[node.body], var)
      @analysis.constrain(node.else_body.pos, @analysis[node.else_body], var)
    end

    def visit(ctx, node : AST::Jump)
      # Conceptually, a jump node's result is the bottom type, since it
      # returns no possible value to its outer expression.
      #
      # In the world of caps, `iso` is our bottom type, meaning it can satisfy
      # any possible cap - which is appropriate only because we know that
      # the code that receives this fake iso is unreachable.
      @analysis[node] = CapLiteral.iso

      case node.kind
      when AST::Jump::Kind::Error
        # TODO: link the term's value to the error-catch block catching it.
      when AST::Jump::Kind::Break
        # TODO: link the term's value to the loop or yield block catching it.
      when AST::Jump::Kind::Next
        # TODO: link the term's value to the loop or yield block catching it.
      when AST::Jump::Kind::Return
        @analysis.observe_early_return(node)
      else
        raise NotImplementedError.new(node.kind)
      end
    end

    def visit(ctx, node : AST::Yield)
      @analysis.observe_yield(node)
    end

    def visit(ctx, node : AST::FieldRead | AST::FieldWrite | AST::FieldDisplace)
      @analysis.observe_field_access(node)
    end

    def visit(ctx, node : AST::Call)
      @analysis.observe_call(node)
    end

    def visit(ctx, node)
      raise NotImplementedError.new(node.class)
    end
  end

  class Pass < Compiler::Pass::Analyze(Analysis, Analysis, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Analysis
      infer = ctx.infer[t_link]
      refer_type = ctx.refer_type[t_link]
      deps = {infer, refer_type}
      prev = ctx.prev_ctx.try(&.caps)

      maybe_from_type_alias_cache(ctx, prev, t, t_link, deps) do
        Visitor.new(Analysis.new(t_link), *deps)
          .tap(&.run_for_type_alias(ctx, t))
          .analysis
      end
    end

    def analyze_type(ctx, t, t_link) : Analysis
      infer = ctx.infer[t_link]
      refer_type = ctx.refer_type[t_link]
      deps = {infer, refer_type}
      prev = ctx.prev_ctx.try(&.caps)

      maybe_from_type_cache(ctx, prev, t, t_link, deps) do
        Visitor.new(Analysis.new(t_link), *deps)
          .tap(&.run_for_type(ctx, t))
          .analysis
      end
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      infer = ctx.infer[f_link]
      refer_type = ctx.refer_type[f_link]
      refer = ctx.refer[f_link]
      classify = ctx.classify[f_link]
      deps = {infer, refer_type, refer, classify}
      prev = ctx.prev_ctx.try(&.caps)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(Analysis.new(f_link, t_analysis), *deps)
          .tap(&.run_for_function(ctx, f))
          .analysis
      end
    end
  end
end
