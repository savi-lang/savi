class Mare::Compiler::Infer
  abstract class Info
    property pos : Source::Pos = Source::Pos.none

    abstract def resolve!(ctx : Context, infer : ForFunc) : MetaType
    abstract def within_domain!(
      ctx : Context,
      infer : ForFunc,
      use_pos : Source::Pos,
      constraint_pos : Source::Pos,
      constraint : MetaType,
      aliases : Int32,
    )

    def meta_type_within_domain!(
      ctx : Context,
      meta_type : MetaType,
      use_pos : Source::Pos,
      constraint_pos : Source::Pos,
      constraint : MetaType,
      aliases : Int32,
    )
      orig_meta_type = meta_type
      if aliases > 0
        meta_type = meta_type.strip_ephemeral.alias
        alias_distinct = meta_type != orig_meta_type
      else
        meta_type = meta_type.ephemeralize
      end

      return if meta_type.within_constraints?(ctx, [constraint])

      because_of_alias = alias_distinct &&
        orig_meta_type.ephemeralize.not_nil!.within_constraints?(ctx, [constraint])

      extra = [
        {constraint_pos,
          "it is required here to be a subtype of #{constraint.show_type}"},
        {self, "but the type of the expression " \
          "#{"(when aliased) " if alias_distinct}was #{meta_type.show_type}"},
      ]

      if because_of_alias
        extra.concat [
          {Source::Pos.none,
            "this would be allowed if this reference didn't get aliased"},
          {Source::Pos.none,
            "did you forget to consume the reference?"},
        ]
      end

      Error.at use_pos,
        "The type of this expression doesn't meet the constraints imposed on it",
        extra
    end
  end

  class Unreachable < Info
    INSTANCE = new
    def self.instance; INSTANCE end

    def resolve!(ctx : Context, infer : ForFunc) : MetaType
      MetaType.new(MetaType::Unsatisfiable.instance)
    end

    def within_domain!(
      ctx : Context,
      infer : ForFunc,
      use_pos : Source::Pos,
      constraint_pos : Source::Pos,
      constraint : MetaType,
      aliases : Int32,
    )
      # Do nothing; we're already unsatisfiable...
    end
  end

  abstract class DynamicInfo < Info
    @already_resolved : MetaType?
    @domain_constraints = [] of Tuple(Source::Pos, Source::Pos, MetaType, Int32)
    getter domain_constraints

    def describe_domain_constraints
      raise "already resolved" if @already_resolved

      @domain_constraints.map do |c|
        {c[1], "it is required here to be a subtype of #{c[2].show_type}"}
      end.to_h.to_a
    end

    def first_domain_constraint_pos
      raise "already resolved" if @already_resolved

      @domain_constraints.first[1]
    end

    def total_domain_constraint(ctx)
      raise "already resolved" if @already_resolved

      MetaType.new_intersection(@domain_constraints.map(&.[2]))
    end

    # Must be implemented by the child class as an required hook.
    abstract def describe_kind : String

    # May be implemented by the child class as an optional hook.
    def adds_alias; 0 end

    # Must be implemented by the child class as an required hook.
    abstract def inner_resolve!(ctx : Context, infer : ForFunc)

    # May be implemented by the child class as an optional hook.
    def after_resolve!(ctx : Context, infer : ForFunc, meta_type : MetaType); end

    # This method is *not* intended to be overridden by the child class;
    # please override the after_resolve! method instead.
    private def finish_resolve!(ctx : Context, infer : ForFunc, meta_type : MetaType)
      # Run the optional hook in case the child class defined something here.
      after_resolve!(ctx, infer, meta_type)

      # Save the result of the resolution.
      @already_resolved = meta_type

      # Clear the domain constraint information to save memory;
      # we won't need to use this information again.
      @domain_constraints.clear

      meta_type
    end

    # The final MetaType must meet all constraints that have been imposed.
    def resolve!(ctx : Context, infer : ForFunc) : MetaType
      return @already_resolved.not_nil! if @already_resolved

      meta_type = inner_resolve!(ctx, infer)
      return finish_resolve!(ctx, infer, meta_type) if domain_constraints.empty?

      use_pos = domain_constraints.first[0]

      # TODO: print a different error message when the domain constraints are
      # internally conflicting, even before adding this meta_type into the mix.

      total_domain_constraint = total_domain_constraint(ctx).simplify(ctx)

      meta_type_ephemeral = meta_type.ephemeralize

      if !meta_type_ephemeral.within_constraints?(ctx, [total_domain_constraint])
        extra = describe_domain_constraints
        extra << {pos,
          "but the type of the #{describe_kind} was #{meta_type.show_type}"}

        Error.at use_pos, "The type of this expression " \
          "doesn't meet the constraints imposed on it",
            extra
      end

      # If aliasing makes a difference, we need to evaluate each constraint
      # that has nonzero aliases with an aliased version of the meta_type.
      if meta_type != meta_type.strip_ephemeral.alias
        meta_type_alias = meta_type.strip_ephemeral.alias

        # TODO: Do we need to do anything here to weed out union types with
        # differing capabilities of compatible terms? Is it possible that
        # the type that fulfills the total_domain_constraint is not compatible
        # with the ephemerality requirement, while some other union member is?

        domain_constraints.each do |use_pos, _, constraint, aliases|
          if aliases > 0
            if !meta_type_alias.within_constraints?(ctx, [constraint])
              extra = describe_domain_constraints
              extra << {pos,
                "but the type of the #{describe_kind} " \
                "(when aliased) was #{meta_type_alias.show_type}"
              }

              Error.at use_pos, "This aliasing violates uniqueness " \
                "(did you forget to consume the variable?)",
                extra
            end
          end
        end
      end

      finish_resolve!(ctx, infer, meta_type)
    end

    # May be implemented by the child class as an optional hook.
    def after_within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      if @already_resolved
        meta_type_within_domain!(
          ctx,
          @already_resolved.not_nil!,
          use_pos,
          constraint_pos,
          constraint,
          aliases,
        )
      else
        @domain_constraints << {use_pos, constraint_pos, constraint, aliases + adds_alias}

        after_within_domain!(ctx, infer, use_pos, constraint_pos, constraint, aliases + adds_alias)
      end
    end
  end

  abstract class NamedInfo < DynamicInfo
    @explicit : MetaType?
    @upstreams = [] of Tuple(AST::Node, Source::Pos)

    def initialize(@pos)
    end

    def explicit?
      @explicit
    end

    def adds_alias; 1 end

    def first_viable_constraint_pos : Source::Pos
      @domain_constraints[0]?.try(&.[0]) ||
      @upstreams[0]?.try(&.[1]) ||
      @pos
    end

    def inner_resolve!(ctx : Context, infer : ForFunc)
      explicit = @explicit

      if explicit
        if !explicit.cap_only?
          # If we have an explicit type that is more than just a cap, return it.
          return explicit
        elsif !@upstreams.empty?
          # If there are upstreams, use the explicit cap applied to the type
          # of the first upstream expression, which becomes canonical.
          return (
            infer[@upstreams.first[0]].resolve!(ctx, infer)
            .strip_cap.intersect(explicit).strip_ephemeral
            .strip_ephemeral
          )
        else
          # If we have no upstreams and an explicit cap, return
          # the empty trait called `Any` intersected with that cap.
          any = MetaType.new_nominal(infer.reified_type(infer.prelude_type("Any")))
          return any.intersect(explicit)
        end
      elsif !@upstreams.empty?
        # If we only have upstreams to go on, return the first upstream type.
        return infer[@upstreams.first[0]].resolve!(ctx, infer).strip_ephemeral
      elsif !domain_constraints.empty?
        # If we only have domain constraints to, just do our best with those.
        return total_domain_constraint(ctx).simplify(ctx).strip_ephemeral
      end

      # If we get here, we've failed and don't have enough info to continue.
      Error.at self,
        "This #{describe_kind} needs an explicit type; it could not be inferred"
    end

    def after_resolve!(ctx : Context, infer : ForFunc, meta_type : MetaType)
      # TODO: Verify all upstreams instead of just beyond 1?
      if @upstreams.size > 1
        @upstreams[1..-1].each do |other_upstream, other_upstream_pos|
          infer[other_upstream].within_domain!(ctx, infer, other_upstream_pos, pos, meta_type.strip_ephemeral, 0) # TODO: should we really use 0 here?

          other_mt = infer[other_upstream].resolve!(ctx, infer)
          raise "sanity check" unless other_mt.subtype_of?(ctx, meta_type)
        end
      end
    end

    def set_explicit(explicit_pos : Source::Pos, explicit : MetaType)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" unless @upstreams.empty?

      @explicit = explicit
      @pos = explicit_pos
    end

    def after_within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      return if @explicit

      @upstreams.each do |upstream, upstream_pos|
        infer[upstream].within_domain!(ctx, infer, use_pos, constraint_pos, constraint, aliases)
      end
    end

    def assign(ctx : Context, infer : ForFunc, rhs : AST::Node, rhs_pos : Source::Pos)
      infer[rhs].within_domain!(
        ctx,
        infer,
        rhs_pos,
        @pos,
        @explicit.not_nil!,
        0,
      ) if @explicit

      @upstreams << {rhs, rhs_pos}
    end
  end

  class Fixed < Info
    property inner : MetaType

    def initialize(@pos, @inner)
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @inner
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, @inner, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class Self < Info
    property inner : MetaType
    property domain_constraints : Array(Tuple(Source::Pos, MetaType))

    def initialize(@pos, @inner)
      @domain_constraints = [] of Tuple(Source::Pos, MetaType)
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @inner
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      @domain_constraints << {constraint_pos, constraint}

      meta_type_within_domain!(ctx, @inner, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class Literal < DynamicInfo
    def describe_kind; "literal value" end

    def initialize(@pos, @possible : MetaType)
    end

    def inner_resolve!(ctx : Context, infer : ForFunc)
      # Literal values (such as numeric literals) sometimes have
      # an ambiguous type. Here, we  intersect with the domain constraints
      # to (hopefully) arrive at a single concrete type to return.
      meta_type = total_domain_constraint(ctx).intersect(@possible).simplify(ctx)

      # If we don't satisfy the constraints, leave it to DynamicInfo.resolve!
      # to print a consistent error message instead of printing it here.
      return @possible if meta_type.unsatisfiable?

      if !meta_type.singular?
        Error.at self,
          "This literal value couldn't be inferred as a single concrete type",
          describe_domain_constraints.push({pos,
            "and the literal itself has an intrinsic type of #{meta_type.show_type}"})
      end

      meta_type
    end
  end

  class FuncBody < NamedInfo
    def describe_kind; "function body" end
  end

  class Local < NamedInfo
    def describe_kind; "local variable" end
  end

  class Param < NamedInfo
    def describe_kind; "parameter" end

    def verify_arg(ctx : Context, infer : ForFunc, arg_infer : ForFunc, arg : AST::Node, arg_pos : Source::Pos)
      arg = arg_infer[arg]
      arg.within_domain!(ctx, arg_infer, arg_pos, @pos, resolve!(ctx, infer), 0)
    end
  end

  class Field < NamedInfo
    def describe_kind; "field reference" end
  end

  class FieldRead < Info
    def initialize(@field : Field, @origin : MetaType)
    end

    def pos
      @field.pos
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @field.resolve!(ctx, infer).viewed_from(@origin).alias
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, resolve!(ctx, infer), use_pos, constraint_pos, constraint, aliases + 1) # TODO: can this +1 be removed?
    end
  end

  class FieldExtract < Info
    def initialize(@field : Field, @origin : MetaType)
    end

    def pos
      @field.pos
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @field.resolve!(ctx, infer).extracted_from(@origin).ephemeralize
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, resolve!(ctx, infer), use_pos, constraint_pos, constraint, aliases - 1)
    end
  end

  class RaiseError < Info
    def initialize(@pos)
    end

    def resolve!(ctx : Context, infer : ForFunc)
      MetaType.new(MetaType::Unsatisfiable.instance)
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      raise "can't constrain RaiseError to a domain"
    end
  end

  class Try < Info
    def initialize(@pos, @body : AST::Node, @else_body : AST::Node)
    end

    def resolve!(ctx : Context, infer : ForFunc)
      MetaType.new_union([
        infer[@body].resolve!(ctx, infer),
        infer[@else_body].resolve!(ctx, infer),
      ])
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      infer[@body].within_domain!(ctx, infer, use_pos, constraint_pos, constraint, aliases) \
        unless infer.jumps.away?(@body)

      infer[@else_body].within_domain!(ctx, infer, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class Choice < Info
    getter clauses : Array(AST::Node)

    def initialize(@pos, @clauses)
    end

    def resolve!(ctx : Context, infer : ForFunc)
      MetaType.new_union(clauses.map { |node| infer[node].resolve!(ctx, infer) })
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      clauses.each do |node|
        next if infer.jumps.away?(node)

        infer[node].within_domain!(ctx, infer, use_pos, constraint_pos, constraint, aliases)
      end
    end
  end

  class TypeParamCondition < Info
    getter bool : MetaType # TODO: avoid needing the caller to supply this
    getter refine : Refer::TypeParam
    getter refine_type : MetaType

    def initialize(@pos, @bool, @refine, @refine_type)
      raise "#{@bool.show_type} is not Bool" unless @bool.show_type == "Bool"
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @bool
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, @bool, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class TypeCondition < Info
    getter bool : MetaType # TODO: avoid needing the caller to supply this
    getter refine : AST::Node
    getter refine_type : MetaType

    def initialize(@pos, @bool, @refine, @refine_type)
      raise "#{@bool.show_type} is not Bool" unless @bool.show_type == "Bool"
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @bool
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, @bool, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class TrueCondition < Info # TODO: dedup with FalseCondition?
    getter bool : MetaType # TODO: avoid needing the caller to supply this

    def initialize(@pos, @bool)
      raise "#{@bool.show_type} is not Bool" unless @bool.show_type == "Bool"
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @bool
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, @bool, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class FalseCondition < Info # TODO: dedup with TrueCondition?
    getter bool : MetaType # TODO: avoid needing the caller to supply this

    def initialize(@pos, @bool)
      raise "#{@bool.show_type} is not Bool" unless @bool.show_type == "Bool"
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @bool
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, @bool, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class Refinement < Info
    getter refine : AST::Node
    getter refine_type : MetaType

    def initialize(@pos, @refine, @refine_type)
    end

    def resolve!(ctx : Context, infer : ForFunc)
      infer[@refine].resolve!(ctx, infer).intersect(@refine_type)
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, resolve!(ctx, infer), use_pos, constraint_pos, constraint, aliases)
    end
  end

  class Consume < Info
    getter local : AST::Node

    def initialize(@pos, @local)
    end

    def resolve!(ctx : Context, infer : ForFunc)
      infer[@local].resolve!(ctx, infer).ephemeralize
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      infer[@local].within_domain!(ctx, infer, use_pos, constraint_pos, constraint, aliases - 1)
    end
  end

  class FromCall < DynamicInfo
    getter lhs : AST::Node
    getter member : String
    getter args_pos : Array(Source::Pos)
    getter args : Array(AST::Node)
    getter ret_value_used : Bool
    @ret : MetaType?
    @ret_pos : Source::Pos? # TODO: remove?

    def initialize(@pos, @lhs, @member, @args, @args_pos, @ret_value_used)
    end

    def describe_kind; "return value" end

    def inner_resolve!(ctx : Context, infer : ForFunc)
      raise "unresolved ret for #{self.inspect}" unless @ret
      @ret.not_nil!
    end

    def set_return(infer : ForFunc, ret_pos : Source::Pos, ret : MetaType)
      @ret_pos = ret_pos
      @ret = ret.ephemeralize
    end
  end

  class FromYield < NamedInfo
    def describe_kind; "yield block result" end
  end

  class ArrayLiteral < DynamicInfo
    getter terms : Array(AST::Node)
    property explicit : MetaType?

    def initialize(@pos, @terms)
      @elem_antecedents = Set(MetaType).new
    end

    def describe_kind; "array literal" end

    def inner_resolve!(ctx : Context, infer : ForFunc)
      array_defn = infer.prelude_type("Array")

      # Determine the lowest common denominator MetaType of all elements.
      elem_mts = terms.map { |term| infer[term].resolve!(ctx, infer) }.uniq
      elem_mt = MetaType.new_union(elem_mts).simplify(ctx)

      # Look for exactly one antecedent type that matches the inferred type.
      # Essentially, this is the correlating "outside" inference with "inside".
      # If such a type is found, it replaces our inferred element type.
      # If no such type is found, stick with what we inferred for now.
      possible_antes = [] of MetaType
      possible_element_antecedents(ctx, infer).each do |ante|
        if elem_mts.empty? || elem_mt.subtype_of?(ctx, ante)
          possible_antes << ante
        end
      end
      if possible_antes.size > 1
        # TODO: nice error for the below:
        raise "too many possible antecedents"
      elsif possible_antes.size == 1
        elem_mt = possible_antes.first
      else
        # Leave elem_mt alone and let it ride.
      end

      if elem_mt.unsatisfiable?
        Error.at pos,
          "The type of this empty array literal could not be inferred " \
          "(it needs an explicit type)"
      end

      # Now that we have the element type to use, construct the result.
      rt = infer.reified_type(infer.prelude_type("Array"), [elem_mt])
      mt = MetaType.new(rt)

      # Reach the functions we will use during CodeGen.
      ["new", "<<"].each do |f_name|
        f = rt.defn(ctx).find_func!(f_name)
        f_link = f.make_link(rt.link)
        ctx.infer.for_func(ctx, rt, f_link, MetaType.cap(f.cap.value)).run
        infer.extra_called_func!(pos, rt, f_link)
      end

      mt
    end

    def after_within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      antecedents = possible_element_antecedents(ctx, infer)
      return if antecedents.empty?

      terms.each do |term|
        infer[term].within_domain!(
          ctx,
          infer,
          use_pos,
          constraint_pos,
          MetaType.new_union(antecedents),
          0,
        )
      end
    end

    private def possible_element_antecedents(ctx, infer) : Array(MetaType)
      results = [] of MetaType

      total_domain_constraint(ctx).each_reachable_defn.to_a.each do |rt|
        # TODO: Support more element antecedent detection patterns.
        if rt.link == infer.prelude_type("Array") \
        && rt.args.size == 1
          results << rt.args.first
        end
      end

      results
    end
  end
end
