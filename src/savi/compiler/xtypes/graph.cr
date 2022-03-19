require "../pass/analyze"

##
# WIP: This pass is intended to be a future replacement for the Infer pass,
# but it is still a work in progress and isn't in the main compile path yet.
#
# Also, experimentation is under way with a different approach to this pass.
# This pass has been named XTypes and the Types pass is for new experimentation.
#
module Savi::Compiler::XTypes::Graph
  struct Analysis
    getter scope : TypeVariable::Scope
    getter parent : StructRef(Analysis)?
    getter! for_self : AlgebraicType
    getter! type_param_vars : Array(TypeVariable)
    getter! field_type_vars : Hash(String, TypeVariable)
    getter! param_vars : Array(TypeVariable)
    getter! receiver_cap_var : TypeVariable
    getter! return_var : TypeVariable
    getter! yield_vars : Array(TypeVariable)
    getter! yield_result_var : TypeVariable

    def initialize(@scope, parent : Analysis? = nil)
      @parent = parent ? StructRef(Analysis).new(parent) : nil
      @sequence_number = 0u64

      @by_node = {} of AST::Node => AlgebraicType
      @local_vars_by_ref = {} of Refer::Info => TypeVariable
      @type_vars = [] of TypeVariable
      @edge_type_vars = [] of TypeVariable
      @assertions = Set({Source::Pos, AlgebraicType, AlgebraicType}).new
    end

    def [](node : AST::Node); @by_node[node]; end
    def []?(node : AST::Node); @by_node[node]?; end

    protected def []=(node : AST::Node, alg : AlgebraicType)
      @by_node[node] = alg
    end

    def show_type_variables_list
      String.build { |output| show_type_variables_list(output) }
    end

    def show_type_variables_list(output)
      parent = @parent
      if parent
        parent.show_type_variables_list(output)
        output << "~~~\n"
      end

      (@edge_type_vars + @type_vars).each_with_index { |var, index|
        output << "\n" if index > 0
        var.show_info(output)
      }
      if @assertions.any?
        output << "~~~\n"
        @assertions.each_with_index { |(pos, sub, sup), index|
          output << "\n" if index > 0
          output << "  #{sub.show} <: #{sup.show}\n"
          output << "  #{pos.show.split("\n")[1..-1].join("\n  ")}\n"
        }
      end
    end

    private def new_type_var(nickname)
      TypeVariable.new(nickname, @scope, @sequence_number += 1).tap { |var|
        @type_vars << var
      }
    end

    private def new_edge_type_var(nickname)
      TypeVariable.new(nickname, @scope, @sequence_number += 1).tap { |var|
        @edge_type_vars << var
      }
    end

    private def new_cap_var(nickname)
      TypeVariable.new(nickname, @scope, @sequence_number += 1,
        is_cap_var: true
      )
    end

    protected def init_type_self(ctx, visitor : Visitor, params : AST::Group?)
      @type_param_vars = params.try(&.terms.map { |param|
        ident = AST::Extract.type_param(param).first
        var = new_type_var(ident.value)
        var.is_input_var = true
        var
      })

      @for_self = NominalType.new(
        scope.as(Program::Type::Link),
        @type_param_vars.try(&.map { |var|
          TypeVariableRef.new(var).as(AlgebraicType)
        }),
      )

      params.try(&.terms.each_with_index { |param, index|
        ident, explicit, default = AST::Extract.type_param(param)
        var = @type_param_vars.not_nil![index]

        explicit_type = visitor.read_type_expr(ctx, explicit) if explicit
        default_type = visitor.read_type_expr(ctx, default) if default

        @by_node[param] = TypeVariableRef.new(var)
        @by_node[ident] = TypeVariableRef.new(var)
        @by_node[explicit] = explicit_type.not_nil! if explicit
        @by_node[default] = default_type.not_nil! if default

        var.observe_constraint_at(explicit.pos, explicit_type.not_nil!) if explicit
      })
    end

    protected def init_type_fields(ctx, visitor : Visitor, fields : Array(Program::Function))
      @field_type_vars = fields.map { |f|
        {f.ident.value, new_type_var(f.ident.value)}
      }.to_h
    end

    protected def init_func_self(cap : String, pos : Source::Pos)
      @for_self = begin
        @receiver_cap_var = self_cap = new_cap_var("@")
        self_cap.is_input_var = true

        # If it's a `:fun box`, we interpret it as a type variable constrained
        # to be one of the caps in the set called `read` (`ref`, `val`, `box`).
        # Otherwise, we bind it directly to the concrete cap that was given.
        if cap == "box"
          self_cap.observe_constraint_at(pos,
            Union.from([NominalCap::VAL, NominalCap::REF, NominalCap::BOX])
          )
        else
          self_cap.observe_binding_at(pos, NominalCap.from_string(cap))
        end

        self_type = @parent.not_nil!.value.for_self
        self_type.intersect(TypeVariableRef.new(self_cap))
      end.as(AlgebraicType)

      @param_vars = [] of TypeVariable
    end

    protected def init_func_return_var(ctx, visitor : Visitor, f : Program::Function)
      @return_var = var = new_type_var("return")

      ret = f.ret
      if ret
        explicit_type = visitor.read_type_expr(ctx, ret)
        if f.body
          var.observe_constraint_at(ret.pos, explicit_type)
        else
          var.observe_binding_at(ret.pos, explicit_type)
        end
      end
    end

    protected def init_constructor_return_var(
      visitor : Visitor,
      cap_ident : AST::Identifier,
    )
      @return_var = var = new_type_var("return")

      constructed_type = @parent.not_nil!.value.for_self.intersect(
        visitor.read_type_expr_cap(cap_ident).not_nil!
      )
      var.observe_binding_at(cap_ident.pos, constructed_type)
    end

    protected def observe_natural_return(node : AST::Group)
      self.return_var.observe_assignment_at(node.terms.last.pos, @by_node[node])
    end

    protected def observe_early_return(node : AST::Jump)
      self.return_var.observe_assignment_at(node.pos, @by_node[node.term])
    end

    protected def observe_yield(node : AST::Yield)
      vars = @yield_vars ||= [] of TypeVariable
      node.terms.each_with_index { |term, index|
        var = vars[index]? || begin
          v = new_type_var("yield:#{index + 1}")
          vars << v
          v
        end
        var.observe_assignment_at(node.pos, @by_node[term])
      }

      result_var = @yield_result_var ||= new_type_var("yield:result")
      @by_node[node] = TypeVariableRef.new(result_var)
    end

    protected def observe_constrained_literal(node, var_name, supertype)
      var = new_type_var(var_name)
      @by_node[node] = TypeVariableRef.new(var)
      var.observe_constraint_at(node.pos, supertype)
    end

    protected def observe_assert_bool(ctx, node)
      t_link = ctx.namespace.core_savi_type(ctx, "Bool")
      bool = NominalType.new(t_link).intersect(NominalCap::VAL)
      @assertions << {node.pos, @by_node[node], bool}
    end

    protected def observe_self_reference(node, ref)
      @by_node[node] = for_self
    end

    protected def observe_local_reference(node, ref)
      var = @local_vars_by_ref[ref] ||= new_type_var(ref.name)
      @by_node[node] = TypeVariableRef.new(var).aliased
    end

    protected def observe_local_consume(node, ref)
      var = @local_vars_by_ref[ref] ||= new_type_var(ref.name)
      @by_node[node] = TypeVariableRef.new(var)
    end

    protected def observe_assignment(node, ref)
      var = @local_vars_by_ref[ref]

      explicit = AST::Extract.param(node.lhs)[1]
      var.observe_binding_at(explicit.pos, @by_node[explicit]) if explicit

      rhs = @by_node[node.rhs].stabilized
      var.observe_assignment_at(node.pos, rhs)

      @by_node[node] = TypeVariableRef.new(var).aliased
    end

    protected def observe_param(node, ref)
      ident, explicit, default = AST::Extract.param(node)
      var = @local_vars_by_ref[ref]
      param_vars << var

      if explicit
        # Params differ from local variables in that their explicit type
        # creates a constraint rather than a fully-equivalent binding.
        var.observe_constraint_at(explicit.pos, @by_node[explicit])

        # However, they do set up the explicit type as being the summary.
        var.eager_constraint_summary = @by_node[explicit]
      end

      var.observe_assignment_at(node.pos, @by_node[default].stabilized) if default

      @by_node[node] = TypeVariableRef.new(var).aliased
    end

    protected def observe_field_access(node)
      parent = @parent.not_nil!.value
      var = parent.field_type_vars[node.value]
      case node
      when AST::FieldRead
        @by_node[node] = TypeVariableRef.new(var).aliased.viewed_from(@for_self)
      when AST::FieldWrite
        @by_node[node] = TypeVariableRef.new(var).aliased
        var.observe_assignment_at(node.pos, @by_node[node.rhs])
      when AST::FieldDisplace
        @by_node[node] = TypeVariableRef.new(var)
        var.observe_assignment_at(node.pos, @by_node[node.rhs])
      end
    end

    protected def observe_field_func(ctx, visitor, f : Program::Function)
      var = @parent.not_nil!.field_type_vars[f.ident.value]

      f.ret.try { |ret|
        var.observe_binding_at(ret.pos, visitor.read_type_expr(ctx, ret))
      }
      f.body.try { |body|
        var.observe_assignment_at(body.pos, @by_node[body])
      }
    end

    protected def observe_call(node)
      receiver_type = @by_node[node.receiver]

      node.args.try(&.terms.each_with_index { |term, index|
        param_var = new_type_var("#{node.ident.value}(#{index})")
        param_var.observe_toward_call_arg_at(node.pos, node, receiver_type, index)
        param_var.observe_assignment_at(term.pos, @by_node[term])
      })

      var = new_type_var(node.ident.value)
      var.observe_from_call_return_at(node.pos, node, receiver_type)
      @by_node[node] = TypeVariableRef.new(var)
    end

    protected def observe_array_literal(ctx, node)
      var = new_type_var("array:group")
      elem_var = new_type_var("array:elem")

      @by_node[node] = TypeVariableRef.new(var)

      array_nominal = NominalType.new(
        ctx.namespace.core_savi_type(ctx, "Array"),
        [TypeVariableRef.new(elem_var).as(AlgebraicType)]
      )
      array_type = array_nominal.intersect(
        array_nominal.intersect(NominalCap::ISO)
          .unite(array_nominal.intersect(NominalCap::VAL))
          .unite(array_nominal.intersect(NominalCap::REF))
      )
      var.observe_constraint_at(node.pos, array_type)

      node.terms.each { |elem|
        elem_var.observe_assignment_at(node.pos, @by_node[elem])
      }
    end
  end

  class Visitor < AST::Visitor
    getter analysis
    private getter refer_type : ReferType::Analysis
    private getter! classify : Classify::Analysis # only present within a func
    private getter! refer : Refer::Analysis       # only present within a func

    def initialize(
      @analysis : Analysis,
      @refer_type,
      @classify = nil,
      @refer = nil,
    )
    end

    def run_for_type_alias(ctx : Context, t : Program::TypeAlias)
      # TODO: Allow running this pass for more than just the root package.
      # We restrict this for now while we are building out the pass because
      # we don't want to deal with all of the complicated forms in Savi core.
      # We want to stick to the simple forms in the compiler pass specs for now.
      root_package = ctx.root_package.source_package
      return unless t.ident.pos.source.package == root_package

      raise NotImplementedError.new("run_for_type_alias")
    end

    def run_for_type(ctx : Context, t : Program::Type)
      @analysis.init_type_self(ctx, self, t.params)
      @analysis.init_type_fields(ctx, self, t.functions.select(&.has_tag?(:field)))
    end

    def run_for_function(ctx : Context, f : Program::Function)
      @analysis.init_func_self(f.cap.value, f.cap.pos)
      if f.has_tag?(:constructor)
        @analysis.init_constructor_return_var(self, f.cap)
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

    def core_savi_type(ctx, name, cap, args = nil)
      t_link = ctx.namespace.core_savi_type(ctx, name)
      NominalType.new(t_link, args).intersect(cap)
    end

    def visit_any?(ctx, node)
      # Read type expressions using a different, top-down kind of approach.
      # This prevents the normal depth-first visit when false is returned.
      if !@classify || classify.type_expr?(node)
        @analysis[node] = read_type_expr(ctx, node)
        false
      else
        true
      end
    end

    def read_type_expr_cap(node : AST::Identifier)
      case node.value

      when "iso" then NominalCap::ISO
      when "val" then NominalCap::VAL
      when "ref" then NominalCap::REF
      when "box" then NominalCap::BOX
      when "tag" then NominalCap::TAG
      when "non" then NominalCap::NON

      when "any"   then Union.from([NominalCap::ISO, NominalCap::VAL, NominalCap::REF, NominalCap::BOX, NominalCap::TAG, NominalCap::NON])
      when "alias" then Union.from([NominalCap::VAL, NominalCap::REF, NominalCap::BOX, NominalCap::TAG, NominalCap::NON])
      when "send"  then Union.from([NominalCap::ISO, NominalCap::VAL, NominalCap::TAG, NominalCap::NON])
      when "share" then Union.from([NominalCap::VAL, NominalCap::TAG, NominalCap::NON])
      when "read"  then Union.from([NominalCap::VAL, NominalCap::REF, NominalCap::BOX])

      else nil
      end
    end

    def read_type_expr(ctx, node : AST::Identifier)
      ref = @refer_type[node]?

      case ref
      when Refer::Self
        @analysis.for_self
      when Refer::Type
        t = ref.link.resolve(ctx)
        NominalType.new(ref.link).intersect(read_type_expr_cap(t.cap).not_nil!)
      when Refer::TypeAlias
        NominalCap::NON # TODO: Lazy unwrapping of recursive type aliases
      when Refer::TypeParam
        analysis = @analysis
        while analysis.scope != ref.parent_link
          analysis = analysis.parent.not_nil!.value
        end
        TypeVariableRef.new(analysis.type_param_vars[ref.index])
      when nil
        cap = read_type_expr_cap(node)
        if cap
          cap
        else
          ctx.error_at node, "This type couldn't be resolved"
          NominalCap::NON
        end
      else
        raise NotImplementedError.new(ref.class)
      end
    end

    def read_type_expr(ctx, node : AST::Relate)
      case node.op.value
      when "->"
        lhs = read_type_expr(ctx, node.lhs)
        rhs = read_type_expr(ctx, node.rhs)
        rhs.viewed_from(lhs)
      when "'"
        lhs = read_type_expr(ctx, node.lhs)
        cap_ident = node.rhs.as(AST::Identifier)
        case cap_ident.value
        when "aliased"
          lhs.aliased
        else
          cap = read_type_expr_cap(cap_ident)
          if cap
            lhs.override_cap(cap)
          else
            ctx.error_at cap_ident, "This type couldn't be resolved"
            lhs
          end
        end
      else
        raise NotImplementedError.new(node.op.value)
      end
    end

    def read_type_expr(ctx, node : AST::Qualify)
      raise NotImplementedError.new(node.to_a) unless node.group.style == "("

      args = node.group.terms.map { |arg|
        read_type_expr(ctx, arg).as(AlgebraicType)
      }
      base = read_type_expr(ctx, node.term).as(IntersectionBasic)
      IntersectionBasic.new(
        NominalType.new(base.nominal_type.link, args),
        base.nominal_cap,
      )
    end

    def read_type_expr(ctx, node : AST::Group)
      case node.style
      when "("
        raise NotImplementedError.new("multiple terms in type expr group") \
          unless node.terms.size == 1
        read_type_expr(ctx, node.terms.first)
      when "|"
        Union.from(node.terms.map { |term| read_type_expr(ctx, term) })
      else
        raise NotImplementedError.new(node.style)
      end
    end

    def read_type_expr(ctx, node)
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
          t = ref.link.resolve(ctx)
          @analysis[node] = NominalType.new(ref.link).intersect(
            read_type_expr_cap(t.cap).not_nil!
          )
        else
          # A type reference whose value is used and is not itself a value
          # must be marked non, rather than having the default cap for that type.
          # This is used when we pass a type around as if it were a value,
          # where that value is a stateless singleton able to call `:fun non`s.
          @analysis[node] = NominalType.new(ref.link).intersect(NominalCap::NON)
        end
      when Refer::TypeParam
        analysis = @analysis
        while analysis.scope != ref.parent_link
          analysis = analysis.parent.not_nil!.value
        end
        @analysis[node] = TypeVariableRef.new(
          analysis.type_param_vars[ref.index]
        )
      else
        raise NotImplementedError.new(ref.class)
      end
    end

    def visit(ctx, node : AST::LiteralCharacter)
      type = core_savi_type(ctx, "Numeric.Convertible", NominalCap::VAL)
      @analysis.observe_constrained_literal(node, "char:#{node.value}", type)
    end

    def visit(ctx, node : AST::LiteralInteger)
      type = core_savi_type(ctx, "Numeric.Convertible", NominalCap::VAL)
      @analysis.observe_constrained_literal(node, "num:#{node.value}", type)
    end

    def visit(ctx, node : AST::LiteralFloat)
      type = core_savi_type(ctx, "F64", NominalCap::VAL).unite(
        core_savi_type(ctx, "F32", NominalCap::VAL)
      )
      @analysis.observe_constrained_literal(node, "float:#{node.value}", type)
    end

    def visit(ctx, node : AST::LiteralString)
      case node.prefix_ident.try(&.value)
      when nil
        @analysis[node] = core_savi_type(ctx, "String", NominalCap::VAL)
      when "b"
        @analysis[node] = core_savi_type(ctx, "Bytes", NominalCap::VAL)
      else
        ctx.error_at node.prefix_ident.not_nil!,
          "This type of string literal is not known; please remove this prefix"
        @analysis[node] = core_savi_type(ctx, "String", NominalCap::VAL)
      end
    end

    def visit(ctx, node : AST::Group)
      case node.style
      when "|"
        # Do nothing here - we'll handle it in one of the parent nodes.
      when "["
        @analysis.observe_array_literal(ctx, node)
      when "(", ":"
        if node.terms.empty?
          @analysis[node] = core_savi_type(ctx, "None", NominalCap::NON)
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
      when "source_code_position_of_argument"
        @analysis[node] = core_savi_type(ctx, "SourceCodePosition", NominalCap::VAL)
      when "reflection_of_type"
        @analysis[node] = core_savi_type(ctx, "ReflectionOfType", NominalCap::VAL, [@analysis[node.term]])
      when "reflection_of_runtime_type_name"
        @analysis[node] = core_savi_type(ctx, "String", NominalCap::VAL)
      when "identity_digest_of"
        @analysis[node] = core_savi_type(ctx, "USize", NominalCap::VAL)
      when "--"
        ref = refer[node.term].as(Refer::Local)
        @analysis.observe_local_consume(node, ref)
      else
        raise NotImplementedError.new(node.op.value)
      end
    end

    def visit(ctx, node : AST::Qualify)
      raise NotImplementedError.new(node.to_a) unless node.group.style == "("

      args = node.group.terms.map { |arg_node| @analysis[arg_node] }

      base = @analysis[node.term].as(IntersectionBasic)
      @analysis[node] = IntersectionBasic.new(
        NominalType.new(base.nominal_type.link, args),
        base.nominal_cap,
      )
    end

    def visit(ctx, node : AST::Relate)
      case node.op.value
      when "EXPLICITTYPE"
        # Do nothing here - we'll handle it in one of the parent nodes.
      when "<:", "!<:"
        # TODO: refine the type in this scope
        @analysis[node] = core_savi_type(ctx, "Bool", NominalCap::VAL)
      when "===", "!=="
        # Just know that the result of this expression is a boolean.
        @analysis[node] = core_savi_type(ctx, "Bool", NominalCap::VAL)
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
      @analysis[node] =
        Union.from(node.list.map { |cond, body| @analysis[body] })
    end

    def visit(ctx, node : AST::Loop)
      @analysis.observe_assert_bool(ctx, node.initial_cond)
      @analysis.observe_assert_bool(ctx, node.repeat_cond)
      @analysis[node] =
        @analysis[node.body].unite(@analysis[node.else_body])
    end

    def visit(ctx, node : AST::Try)
      @analysis[node] =
        @analysis[node.body].unite(@analysis[node.else_body])
    end

    def visit(ctx, node : AST::Jump)
      case node.kind
      when AST::Jump::Kind::Error
        @analysis[node] = JumpsAway.new(node.pos)
      when AST::Jump::Kind::Break
        # TODO: link the term's value to the loop or yield block catching it
        @analysis[node] = JumpsAway.new(node.pos)
      when AST::Jump::Kind::Return
        @analysis.observe_early_return(node)
        @analysis[node] = JumpsAway.new(node.pos)
      else
        puts node.pos.show
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
      refer_type = ctx.refer_type[t_link]
      deps = {refer_type}
      prev = ctx.prev_ctx.try(&.xtypes_graph)

      maybe_from_type_alias_cache(ctx, prev, t, t_link, deps) do
        Visitor.new(Analysis.new(t_link), *deps)
          .tap(&.run_for_type_alias(ctx, t))
          .analysis
      end
    end

    def analyze_type(ctx, t, t_link) : Analysis
      refer_type = ctx.refer_type[t_link]
      deps = {refer_type}
      prev = ctx.prev_ctx.try(&.xtypes_graph)

      maybe_from_type_cache(ctx, prev, t, t_link, deps) do
        Visitor.new(Analysis.new(t_link), *deps)
          .tap(&.run_for_type(ctx, t))
          .analysis
      end
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      refer_type = ctx.refer_type[f_link]
      classify = ctx.classify[f_link]
      refer = ctx.refer[f_link]
      deps = {refer_type, classify, refer}
      prev = ctx.prev_ctx.try(&.xtypes_graph)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(Analysis.new(f_link, t_analysis), *deps)
          .tap(&.run_for_function(ctx, f))
          .analysis
      end
    end
  end
end
