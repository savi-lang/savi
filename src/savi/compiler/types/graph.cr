require "../pass/analyze"

##
# WIP: This pass is intended to be a future replacement for the Infer pass,
# but it is still a work in progress and isn't in the main compile path yet.
#
module Savi::Compiler::Types::Graph
  struct Analysis
    getter scope : TypeVariable::Scope
    getter for_type : StructRef(Analysis)?
    getter! for_self : TypeSimple
    getter! type_param_vars : Array(TypeVariable)
    getter! field_type_vars : Hash(String, TypeVariable)
    getter! param_vars : Array(TypeVariable)
    getter! receiver_var : TypeVariable
    getter! return_var : TypeVariable
    getter! yield_vars : Array(TypeVariable)
    getter! yield_result_var : TypeVariable

    def initialize(@scope, for_type : Analysis? = nil)
      @for_type = for_type ? StructRef(Analysis).new(for_type) : nil
      @sequence_number = 0

      @by_node = {} of AST::Node => TypeSimple
      @local_vars_by_ref = {} of Refer::Info => TypeVariable
      @type_vars = [] of TypeVariable

      @var_lower_bounds = [] of Array({Source::Pos, TypeSimple})
      @var_upper_bounds = [] of Array({Source::Pos, TypeSimple})
      @var_resolution_dependencies = [] of Array(TypeVariable)
      @var_resolution_dependents = [] of Array(TypeVariable)
      @var_call_associations = [] of AST::Call?
      @var_param_associations = [] of Int32
    end

    def [](node : AST::Node); @by_node[node]; end
    def []?(node : AST::Node); @by_node[node]?; end

    protected def []=(node : AST::Node, t : TypeSimple)
      @by_node[node] = t
    end

    def lower_bounds_of(var : TypeVariable)
      case var.scope
      when @scope
        @var_lower_bounds[var.sequence_number - 1]
      when for_type.try(&.value.scope)
        for_type.not_nil!.value.lower_bounds_of(var)
      else
        raise NotImplementedError.new("can't reach properties of foreign vars")
      end
    end

    def upper_bounds_of(var : TypeVariable)
      case var.scope
      when @scope
        @var_upper_bounds[var.sequence_number - 1]
      when for_type.try(&.value.scope)
        for_type.not_nil!.value.upper_bounds_of(var)
      else
        raise NotImplementedError.new("can't reach properties of foreign vars")
      end
    end

    def resolution_dependencies_of(var : TypeVariable)
      case var.scope
      when @scope
        @var_resolution_dependencies[var.sequence_number - 1]
      when for_type.try(&.value.scope)
        for_type.not_nil!.value.resolution_dependencies_of(var)
      else
        raise NotImplementedError.new("can't reach properties of foreign vars")
      end
    end

    def resolution_dependents_of(var : TypeVariable)
      case var.scope
      when @scope
        @var_resolution_dependents[var.sequence_number - 1]
      when for_type.try(&.value.scope)
        for_type.not_nil!.value.resolution_dependents_of(var)
      else
        raise NotImplementedError.new("can't reach properties of foreign vars")
      end
    end

    def call_association_of(var : TypeVariable)
      case var.scope
      when @scope
        @var_call_associations[var.sequence_number - 1]
      when for_type.try(&.value.scope)
        for_type.not_nil!.value.call_association_of(var)
      else
        raise NotImplementedError.new("can't reach properties of foreign vars")
      end
    end

    def param_association_of(var : TypeVariable)
      case var.scope
      when @scope
        @var_param_associations[var.sequence_number - 1]
      when for_type.try(&.value.scope)
        for_type.not_nil!.value.param_association_of(var)
      else
        raise NotImplementedError.new("can't reach properties of foreign vars")
      end
    end

    protected def new_type_var(
      nickname : String,
      for_call : AST::Call? = nil,
      for_param : Int32 = -1,
    )
      TypeVariable.new(nickname, @scope, @sequence_number += 1).tap { |var|
        @type_vars << var
        @var_lower_bounds << [] of {Source::Pos, TypeSimple}
        @var_upper_bounds << [] of {Source::Pos, TypeSimple}
        @var_resolution_dependencies << [] of TypeVariable
        @var_resolution_dependents << [] of TypeVariable
        @var_call_associations << for_call
        @var_param_associations << for_param
      }
    end

    def show_type_variables_list
      String.build { |output| show_type_variables_list(output) }
    end
    def show_type_variables_list(output : IO)
      for_type = @for_type
      if for_type
        for_type.show_type_variables_list(output)
        output << "~~~\n"
      end

      @type_vars.each_with_index { |var, index|
        output << "\n" if index > 0
        show_type_variable(output, var)
      }
    end

    def show_type_variable(var : TypeVariable)
      String.build { |output| show_type_variable(output, var) }
    end
    def show_type_variable(output, var : TypeVariable)
      var.show(output)
      output << "\n"

      call = call_association_of(var)
      if call
        param_index = param_association_of(var)
        if param_index == -1
          output << "  comes from the result of this call:\n  "
          output << call.pos.show.split("\n")[1..-1].join("\n  ")
          output << "\n"
        else
          output << "  goes to param index #{param_index} of this call:\n  "
          output << call.pos.show.split("\n")[1..-1].join("\n  ")
          output << "\n"
        end
      end

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

      dependencies = resolution_dependencies_of(var)
      if dependencies.any?
        output << "  will be further constrained after resolving:\n"
        dependencies.each { |other_var|
          output << "    - "
          other_var.show(output)
          output << "\n"
        }
      end
    end

    protected def init_type_self(ctx, visitor : Visitor, params : AST::Group?)
      @type_param_vars = params.try(&.terms.map { |param|
        ident = AST::Extract.type_param(param).first
        var = new_type_var(ident.value)
        # var.is_input_var = true
        var
      })

      @for_self = TypeNominal.new(
        scope.as(Program::Type::Link),
        @type_param_vars.try(&.map(&.as(TypeSimple))),
      )

      params.try(&.terms.each_with_index { |param, index|
        ident, explicit, default = AST::Extract.type_param(param)
        var = @type_param_vars.not_nil![index]

        explicit_type = visitor.read_type_expr(ctx, explicit) if explicit
        default_type = visitor.read_type_expr(ctx, default) if default

        @by_node[param] = var
        @by_node[ident] = var
        @by_node[explicit] = explicit_type.not_nil! if explicit
        @by_node[default] = default_type.not_nil! if default

        constrain(explicit.pos, var, explicit_type.not_nil!) if explicit
      })
    end

    protected def init_type_fields(ctx, visitor : Visitor, fields : Array(Program::Function))
      @field_type_vars = fields.map { |f|
        {f.ident.value, new_type_var(f.ident.value)}
      }.to_h
    end

    protected def init_func_self(pos : Source::Pos)
      @for_self = begin
        @receiver_var = var = new_type_var("@")
        constrain(pos, var, @for_type.not_nil!.value.for_self)
        var
      end.as(TypeSimple)

      @param_vars = [] of TypeVariable
    end

    protected def init_func_return_var(ctx, visitor : Visitor, f : Program::Function)
      @return_var = var = new_type_var("return")

      ret = f.ret
      if ret
        explicit_type = visitor.read_type_expr(ctx, ret)
        if f.body
          constrain(ret.pos, var, explicit_type)
        else
          constrain_upper_and_lower(ret.pos, var, explicit_type)
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
      vars = @yield_vars ||= [] of TypeVariable
      node.terms.each_with_index { |term, index|
        var = vars[index]? || begin
          v = new_type_var("yield:#{index + 1}")
          vars << v
          v
        end
        constrain(node.pos, @by_node[term], var)
      }

      result_var = @yield_result_var ||= new_type_var("yield:result")
      @by_node[node] = result_var
    end

    protected def observe_constrained_literal(node, var_name, supertype)
      var = new_type_var(var_name)
      constrain(node.pos, var, supertype)
      @by_node[node] = var
    end

    protected def observe_assert_bool(ctx, node)
      bool = TypeNominal.new(ctx.namespace.core_savi_type(ctx, "Bool"))
      constrain(node.pos, @by_node[node], bool)
    end

    protected def observe_self_reference(node, ref)
      @by_node[node] = for_self
    end

    protected def observe_local_reference(node, ref)
      var = @local_vars_by_ref[ref] ||= new_type_var(ref.name)
      @by_node[node] = var
    end

    protected def observe_local_consume(node, ref)
      var = @local_vars_by_ref[ref] ||= new_type_var(ref.name)
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
      var = for_type.field_type_vars[node.value]
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
      var = @for_type.not_nil!.field_type_vars[f.ident.value]

      f.ret.try { |ret|
        constrain_upper_and_lower(ret.pos, var, visitor.read_type_expr(ctx, ret))
      }
      f.body.try { |body|
        constrain(body.pos, @by_node[body], var)
      }
    end

    protected def observe_resolution_dependency(dependent, prerequisite)
      resolution_dependencies_of(dependent) << prerequisite
      resolution_dependents_of(prerequisite) << dependent
    end

    protected def observe_call(call : AST::Call)
      receiver_type = @by_node[call.receiver]

      receiver_type_vars = [] of TypeVariable
      receiver_type.collect_vars_deeply(receiver_type_vars)

      call.args.try(&.terms.each_with_index { |term, index|
        param_var = new_type_var("#{call.ident.value}(#{index})", call, index)
        param_var.is_inner_edge = true

        receiver_type_vars.each { |v|
          observe_resolution_dependency(param_var, v)
        }

        constrain(term.pos, @by_node[term], param_var)
      })

      result_var = new_type_var(call.ident.value, call)
      result_var.is_inner_edge = true

      receiver_type_vars.each { |v|
        observe_resolution_dependency(result_var, v)
      }

      @by_node[call] = result_var
    end

    protected def observe_array_literal(ctx, node)
      var = new_type_var("array:group")
      elem_var = new_type_var("array:elem")

      @by_node[node] = var

      array_type = TypeNominal.new(
        ctx.namespace.core_savi_type(ctx, "Array"),
        [elem_var.as(TypeSimple)]
      )
      constrain(node.pos, var, array_type)

      node.terms.each { |elem|
        constrain(node.pos, @by_node[elem], elem_var)
      }
    end

    protected def constrain_upper_and_lower(
      pos : Source::Pos,
      var : TypeVariable,
      explicit_type : TypeSimple,
    )
      # TODO: Can we bind more efficiently than this?
      constrain(pos, var, explicit_type)
      constrain(pos, explicit_type, var)
    end

    protected def constrain(
      pos : Source::Pos,
      sub : Type,
      sup : Type,
      seen_vars = Set({Type, Type}).new,
    )
      # If the types are identical, there is nothing to be done.
      return if sub == sup

      # If the subtype is the bottom type, or the supertype is the top type,
      # then this constraint is a trivial fact needing no further examination.
      return if sub.is_a?(TypeBottom) || sup.is_a?(TypeTop)

      # Avoid doing duplicate work: if one side or the other is a type variable,
      # check the cache of already constrained type variables, and bail out
      # if we've already started constraining the given variable against the
      # given sub- or super-type it is being constrained with here.
      if sub.is_a?(TypeVariable) || sup.is_a?(TypeVariable)
        return if seen_vars.includes?({sub, sup})
        seen_vars.add({sub, sup})
      end

      # if sub.is_a?(TypeFunction) && sup.is_a?(TypeFunction)
      #   # If both sides are functions, they are compatible if and only if
      #   # the return types and parameter types are compatible with one another.
      #   # Return types are covariant and parameter types are contravariant.
      #   constrain(sub.ret, sup.ret)
      #   constrain(sup.param, sub.param)
      # elsif sub.is_a?(TypeRecord) && sup.is_a?(TypeRecord)
      #   raise NotImplementedError.new("constrain TypeRecord")
      if sub.is_a?(TypeVariable) && sup.is_a?(TypeVariable) \
      && sub.level == sup.level && sub.is_inner_edge
        # If both sides are type variables at the same level,
        # but the subtype is an "inner edge" site (with deferred resolution),
        # prefer putting constraints in the supertype as a special case.
        lower_bounds_of(sup) << {pos, sub}
        upper_bounds_of(sup).each { |b| constrain(b.first, sub, b.last, seen_vars) }
      elsif sub.is_a?(TypeVariable) && sup.level <= sub.level
        # Otherwise, if the subtype is a type variable,
        # prefer putting constraints in the subtype,
        # as long as the subtype is at or above the "level" of the supertype.
        upper_bounds_of(sub) << {pos, sup}
        lower_bounds_of(sub).each { |b| constrain(b.first, b.last, sup, seen_vars) }
      elsif sup.is_a?(TypeVariable) && sub.level <= sup.level
        # Otherwise, try putting constraints in the supertype,
        # as long as the supertype is at or above the "level" of the subtype.
        lower_bounds_of(sup) << {pos, sub}
        upper_bounds_of(sup).each { |b| constrain(b.first, sub, b.last, seen_vars) }
      elsif sub.is_a?(TypeVariable)
        raise NotImplementedError.new("constrain sub variable across levels")
      elsif sup.is_a?(TypeVariable)
        raise NotImplementedError.new("constrain sup variable across levels")
      elsif sup.is_a?(TypeUnion) && sup.members.includes?(sub)
        # This union already contains the subtype, so the constraint is met.
      else
        raise NotImplementedError.new("#{sub.show} <: #{sup.show}\n#{pos.show}")
      end
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
      @analysis.init_func_self(f.ident.pos)
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

    def core_savi_type(ctx, name, args = nil)
      t_link = ctx.namespace.core_savi_type(ctx, name)
      TypeNominal.new(t_link, args)
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

    def ident_is_cap?(node : AST::Identifier)
      case node.value

      when "iso" then true
      when "val" then true
      when "ref" then true
      when "box" then true
      when "tag" then true
      when "non" then true

      when "any"   then true
      when "alias" then true
      when "send"  then true
      when "share" then true
      when "read"  then true

      else false
      end
    end

    def read_type_expr(ctx, node : AST::Identifier)
      ref = @refer_type[node]?

      case ref
      when Refer::Self
        @analysis.for_self
      when Refer::Type
        TypeNominal.new(ref.link)
      when Refer::TypeAlias
        TypeTop.instance # TODO: Lazy unwrapping of recursive type aliases
      when Refer::TypeParam
        analysis = @analysis
        while analysis.scope != ref.parent_link
          analysis = analysis.for_type.not_nil!.value
        end
        analysis.type_param_vars[ref.index]
      when nil
        # Caps are ignored, but we still need to know if an ident is a cap,
        # so that an ident which is not a cap can cause an error.
        ctx.error_at node, "This type couldn't be resolved" \
          unless ident_is_cap?(node)
        TypeTop.instance
      else
        raise NotImplementedError.new(ref.class)
      end
    end

    def read_type_expr(ctx, node : AST::Relate)
      case node.op.value
      when "->"
        # Caps are ignored - just keep the right-hand-side.
        read_type_expr(ctx, node.rhs)
      when "'"
        # Caps are ignored - just keep the left-hand-side.
        read_type_expr(ctx, node.lhs)
      else
        raise NotImplementedError.new(node.op.value)
      end
    end

    def read_type_expr(ctx, node : AST::Qualify)
      raise NotImplementedError.new(node.to_a) unless node.group.style == "("

      args = node.group.terms.map { |arg|
        read_type_expr(ctx, arg).as(TypeSimple)
      }
      base = read_type_expr(ctx, node.term).as(TypeNominal)
      TypeNominal.new(base.link, args)
    end

    def read_type_expr(ctx, node : AST::Group)
      case node.style
      when "("
        raise NotImplementedError.new("multiple terms in type expr group") \
          unless node.terms.size == 1
        read_type_expr(ctx, node.terms.first)
      when "|"
        TypeUnion.from(node.terms.map { |term| read_type_expr(ctx, term) })
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
          @analysis[node] = TypeNominal.new(ref.link)
        else
          # A type reference whose value is used and is not itself a value
          # must be marked non, rather than having the default cap for that type.
          # This is used when we pass a type around as if it were a value,
          # where that value is a stateless singleton able to call `:fun non`s.
          @analysis[node] = TypeNominal.new(ref.link)
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
      type = core_savi_type(ctx, "Numeric.Convertible")
      @analysis.observe_constrained_literal(node, "char:#{node.value}", type)
    end

    def visit(ctx, node : AST::LiteralInteger)
      type = core_savi_type(ctx, "Numeric.Convertible")
      @analysis.observe_constrained_literal(node, "num:#{node.value}", type)
    end

    def visit(ctx, node : AST::LiteralFloat)
      type = TypeUnion.new([
        core_savi_type(ctx, "F64").as(TypeSimple),
        core_savi_type(ctx, "F32").as(TypeSimple),
      ])
      @analysis.observe_constrained_literal(node, "float:#{node.value}", type)
    end

    def visit(ctx, node : AST::LiteralString)
      case node.prefix_ident.try(&.value)
      when nil
        @analysis[node] = core_savi_type(ctx, "String")
      when "b"
        @analysis[node] = core_savi_type(ctx, "Bytes")
      else
        ctx.error_at node.prefix_ident.not_nil!,
          "This type of string literal is not known; please remove this prefix"
        @analysis[node] = core_savi_type(ctx, "String")
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
          @analysis[node] = core_savi_type(ctx, "None")
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
        @analysis[node] = core_savi_type(ctx, "SourceCodePosition")
      when "reflection_of_type"
        @analysis[node] = core_savi_type(ctx, "ReflectionOfType", [@analysis[node.term]])
      when "reflection_of_runtime_type_name"
        @analysis[node] = core_savi_type(ctx, "String")
      when "identity_digest_of"
        @analysis[node] = core_savi_type(ctx, "USize")
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

      base = @analysis[node.term].as(TypeNominal)
      @analysis[node] = TypeNominal.new(base.link, args)
    end

    def visit(ctx, node : AST::Relate)
      case node.op.value
      when "EXPLICITTYPE"
        # Do nothing here - we'll handle it in one of the parent nodes.
      when "<:", "!<:"
        # TODO: refine the type in this scope
        @analysis[node] = core_savi_type(ctx, "Bool")
      when "===", "!=="
        # Just know that the result of this expression is a boolean.
        @analysis[node] = core_savi_type(ctx, "Bool")
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
      @analysis[node] = var = @analysis.new_type_var("choice:result")
      # TODO: Leverage the condition for flow typing.
      node.list.each { |cond, body|
        @analysis.constrain(body.pos, @analysis[body], var)
      }
    end

    def visit(ctx, node : AST::Loop)
      @analysis.observe_assert_bool(ctx, node.initial_cond)
      @analysis.observe_assert_bool(ctx, node.repeat_cond)
      @analysis[node] = var = @analysis.new_type_var("loop:result")
      @analysis.constrain(node.body.pos, @analysis[node.body], var)
      @analysis.constrain(node.else_body.pos, @analysis[node.else_body], var)
    end

    def visit(ctx, node : AST::Try)
      @analysis[node] = var = @analysis.new_type_var("try:result")
      @analysis.constrain(node.body.pos, @analysis[node.body], var)
      @analysis.constrain(node.else_body.pos, @analysis[node.else_body], var)
    end

    def visit(ctx, node : AST::Jump)
      case node.kind
      when AST::Jump::Kind::Error
        @analysis[node] = TypeBottom.instance
      when AST::Jump::Kind::Break
        # TODO: link the term's value to the loop or yield block catching it
        @analysis[node] = TypeBottom.instance
      when AST::Jump::Kind::Return
        @analysis.observe_early_return(node)
        @analysis[node] = TypeBottom.instance
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
      refer_type = ctx.refer_type[t_link]
      deps = {refer_type}
      prev = ctx.prev_ctx.try(&.types_graph)

      maybe_from_type_alias_cache(ctx, prev, t, t_link, deps) do
        Visitor.new(Analysis.new(t_link), *deps)
          .tap(&.run_for_type_alias(ctx, t))
          .analysis
      end
    end

    def analyze_type(ctx, t, t_link) : Analysis
      refer_type = ctx.refer_type[t_link]
      deps = {refer_type}
      prev = ctx.prev_ctx.try(&.types_graph)

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
      prev = ctx.prev_ctx.try(&.types_graph)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(Analysis.new(f_link, t_analysis), *deps)
          .tap(&.run_for_function(ctx, f))
          .analysis
      end
    end
  end
end
