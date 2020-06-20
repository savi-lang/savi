class Mare::Compiler::Infer
  abstract class Info
    property pos : Source::Pos = Source::Pos.none

    abstract def resolve!(ctx : Context, infer : ForFunc) : MetaType

    abstract def add_downstream(
      ctx : Context,
      infer : ForFunc,
      use_pos : Source::Pos,
      info : Info,
      aliases : Int32,
    )

    # TODO: remove this maybe?
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

  abstract class DownstreamableInfo < Info
    # Must be implemented by the child class as an required hook.
    abstract def describe_kind : String

    # May be implemented by the child class as an optional hook.
    def adds_alias; 0 end

    # Values flow downstream as the program executes;
    # the value flowing into a downstream must be a subtype of the downstream.
    # Type information can be inferred in either direction, but certain
    # Info node types are fixed, meaning that they act only as constraints
    # on their upstreams, and are not influenced at all by upstream info nodes.
    @downstreams = [] of Tuple(Source::Pos, Info, Int32)
    def add_downstream(ctx : Context, infer : ForFunc, use_pos : Source::Pos, info : Info, aliases : Int32)
      @downstreams << {use_pos, info, aliases + adds_alias}
      after_add_downstream(ctx, infer, use_pos, info, aliases)
    end
    def downstreams_empty?
      @downstreams.empty?
    end
    def downstream_use_pos
      @downstreams.first[0]
    end

    # May be implemented by the child class as an optional hook.
    def after_add_downstream(ctx : Context, infer : ForFunc, use_pos : Source::Pos, info : Info, aliases : Int32)
    end

    # When we need to take into consideration the downstreams' constraints
    # in order to infer our type from them, we can use this to collect all
    # those constraints into one intersection of them all.
    def total_downstream_constraint(ctx : Context, infer : ForFunc)
      MetaType.new_intersection(
        @downstreams.map { |_, other_info, _|
          infer.resolve(ctx, other_info).as(MetaType)
        }
      ).simplify(ctx) # TODO: is this simplify needed? when is it needed? can it be optimized?
    end

    # TODO: document
    def describe_downstream_constraints(ctx : Context, infer : ForFunc)
      @downstreams.map do |c|
        mt = infer.resolve(ctx, c[1])
        {c[1].pos, "it is required here to be a subtype of #{mt.show_type}"}
      end.to_h.to_a
    end

    # TODO: document
    def within_downstream_constraints!(ctx : Context, infer : ForFunc, meta_type : MetaType)
      if !within_downstream_constraints?(ctx, infer, meta_type)
        extra = describe_downstream_constraints(ctx, infer)
        extra << {pos,
          "but the type of the #{describe_kind} was #{meta_type.show_type}"}

        Error.at downstream_use_pos, "The type of this expression " \
          "doesn't meet the constraints imposed on it",
            extra
      end
    end
    def within_downstream_constraints?(ctx : Context, infer : ForFunc, meta_type : MetaType)
      return true if @downstreams.empty?
      meta_type.within_constraints?(ctx, [total_downstream_constraint(ctx, infer)])
    end
  end

  class Unreachable < Info
    INSTANCE = new
    def self.instance; INSTANCE end

    def resolve!(ctx : Context, infer : ForFunc) : MetaType
      MetaType.new(MetaType::Unsatisfiable.instance)
    end

    def add_downstream(ctx : Context, infer : ForFunc, use_pos : Source::Pos, info : Info, aliases : Int32)
      # Do nothing; we're already unsatisfiable...
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      # Do nothing; we're already unsatisfiable...
    end
  end

  abstract class DynamicInfo < DownstreamableInfo
    @already_resolved : MetaType?
    @domain_constraints = [] of Tuple(Source::Pos, Source::Pos, MetaType, Int32)
    getter domain_constraints

    def describe_domain_constraints(ctx, infer)
      raise "already resolved" if @already_resolved

      describe_downstream_constraints(ctx, infer) +
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
      return finish_resolve!(ctx, infer, meta_type) if downstreams_empty? && domain_constraints.empty?

      use_pos = (domain_constraints[0]?.try(&.[0]) || downstream_use_pos)

      # TODO: print a different error message when the domain constraints are
      # internally conflicting, even before adding this meta_type into the mix.

      total_domain_constraint =
        total_domain_constraint(ctx)
          .intersect(total_downstream_constraint(ctx, infer))
          .simplify(ctx)

      meta_type_ephemeral = meta_type.ephemeralize

      if !meta_type_ephemeral.within_constraints?(ctx, [total_domain_constraint])
        extra = describe_domain_constraints(ctx, infer)
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
              extra = describe_domain_constraints(ctx, infer)
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
        @downstreams.each do |use_pos, other_info, aliases|
          if aliases > 0
            constraint = infer.resolve(ctx, other_info)
            if !meta_type_alias.within_constraints?(ctx, [constraint])
              extra = describe_domain_constraints(ctx, infer)
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
      # .tap { |mt| within_downstream_constraints!(ctx, infer, mt) }
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
    @explicit : Fixed?
    @upstreams = [] of Tuple(AST::Node, Source::Pos)

    def initialize(@pos)
    end

    def explicit? : Bool
      !!@explicit
    end

    def adds_alias; 1 end

    def first_viable_constraint_pos : Source::Pos
      (downstream_use_pos unless downstreams_empty?)
      @domain_constraints[0]?.try(&.[0]) ||
      @upstreams[0]?.try(&.[1]) ||
      @pos
    end

    def inner_resolve!(ctx : Context, infer : ForFunc)
      explicit = @explicit

      if explicit
        explicit_mt = explicit.resolve!(ctx, infer)

        if !explicit_mt.cap_only?
          # If we have an explicit type that is more than just a cap, return it.
          return explicit_mt
        elsif !@upstreams.empty?
          # If there are upstreams, use the explicit cap applied to the type
          # of the first upstream expression, which becomes canonical.
          return (
            infer[@upstreams.first[0]].resolve!(ctx, infer)
            .strip_cap.intersect(explicit_mt).strip_ephemeral
            .strip_ephemeral
          )
        else
          # If we have no upstreams and an explicit cap, return
          # the empty trait called `Any` intersected with that cap.
          any = MetaType.new_nominal(infer.reified_type(infer.prelude_type("Any")))
          return any.intersect(explicit_mt)
        end
      elsif !@upstreams.empty?
        # If we only have upstreams to go on, return the first upstream type.
        return infer[@upstreams.first[0]].resolve!(ctx, infer).strip_ephemeral
      elsif !(downstreams_empty? && domain_constraints.empty?)
        # If we only have domain constraints to, just do our best with those.
        return \
          total_domain_constraint(ctx)
            .intersect(total_downstream_constraint(ctx, infer))
            .simplify(ctx)
            .strip_ephemeral
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

    def set_explicit(explicit_pos : Source::Pos, explicit_mt : MetaType)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" unless @upstreams.empty?

      @explicit = Fixed.new(explicit_pos, explicit_mt.not_nil!)
      @pos = explicit_pos
    end

    def after_within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      return if @explicit

      @upstreams.each do |upstream, upstream_pos|
        infer[upstream].within_domain!(ctx, infer, use_pos, constraint_pos, constraint, aliases)
      end
    end

    def assign(ctx : Context, infer : ForFunc, rhs : AST::Node, rhs_pos : Source::Pos)
      infer[rhs].add_downstream(
        ctx,
        infer,
        rhs_pos,
        @explicit.not_nil!,
        0,
      ) if @explicit

      @upstreams << {rhs, rhs_pos}
    end
  end

  class Fixed < DownstreamableInfo
    property inner : MetaType

    def describe_kind; "expression" end

    def initialize(@pos, @inner)
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @inner
      .tap { |mt| within_downstream_constraints!(ctx, infer, mt) }
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, @inner, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class Self < DownstreamableInfo
    property inner : MetaType
    property domain_constraints : Array(Tuple(Source::Pos, MetaType))

    def describe_kind; "receiver value" end

    def initialize(@pos, @inner)
      @domain_constraints = [] of Tuple(Source::Pos, MetaType)
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @inner
      .tap { |mt| within_downstream_constraints!(ctx, infer, mt) }
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
      total_constraint =
        total_domain_constraint(ctx)
          .intersect(total_downstream_constraint(ctx, infer))

      # Literal values (such as numeric literals) sometimes have
      # an ambiguous type. Here, we  intersect with the domain constraints
      # to (hopefully) arrive at a single concrete type to return.
      meta_type = total_constraint.intersect(@possible).simplify(ctx)

      # If we don't satisfy the constraints, leave it to DynamicInfo.resolve!
      # to print a consistent error message instead of printing it here.
      return @possible if meta_type.unsatisfiable?

      if !meta_type.singular?
        Error.at self,
          "This literal value couldn't be inferred as a single concrete type",
          describe_domain_constraints(ctx, infer).push({pos,
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

  class FieldRead < DownstreamableInfo
    def initialize(@field : Field, @origin : MetaType)
    end

    def describe_kind; "field read" end

    def pos
      @field.pos
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @field.resolve!(ctx, infer).viewed_from(@origin).alias
      .tap { |mt| within_downstream_constraints!(ctx, infer, mt) }
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, resolve!(ctx, infer), use_pos, constraint_pos, constraint, aliases + 1) # TODO: can this +1 be removed?
    end
  end

  class FieldExtract < DownstreamableInfo
    def initialize(@field : Field, @origin : MetaType)
    end

    def describe_kind; "field extraction" end

    def pos
      @field.pos
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @field.resolve!(ctx, infer).extracted_from(@origin).ephemeralize
      .tap { |mt| within_downstream_constraints!(ctx, infer, mt) }
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, resolve!(ctx, infer), use_pos, constraint_pos, constraint, aliases - 1)
    end
  end

  class RaiseError < Info
    def initialize(@pos)
    end

    def describe_kind; "error expression" end

    def resolve!(ctx : Context, infer : ForFunc)
      MetaType.new(MetaType::Unsatisfiable.instance)
    end

    def add_downstream(ctx : Context, infer : ForFunc, use_pos : Source::Pos, info : Info, aliases : Int32)
      raise "can't be downstream of a RaiseError"
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      raise "can't constrain RaiseError to a domain"
    end
  end

  class Try < Info
    def initialize(@pos, @body : AST::Node, @else_body : AST::Node)
    end

    def describe_kind; "try block" end

    def resolve!(ctx : Context, infer : ForFunc)
      MetaType.new_union([
        infer[@body].resolve!(ctx, infer),
        infer[@else_body].resolve!(ctx, infer),
      ])
    end

    def add_downstream(ctx : Context, infer : ForFunc, use_pos : Source::Pos, info : Info, aliases : Int32)
      infer[@body].add_downstream(ctx, infer, use_pos, info, aliases) \
        unless infer.jumps.away?(@body)

      infer[@else_body].add_downstream(ctx, infer, use_pos, info, aliases)
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

    def describe_kind; "choice block" end

    def resolve!(ctx : Context, infer : ForFunc)
      MetaType.new_union(clauses.map { |node| infer[node].resolve!(ctx, infer) })
    end

    def add_downstream(ctx : Context, infer : ForFunc, use_pos : Source::Pos, info : Info, aliases : Int32)
      clauses.each do |node|
        next if infer.jumps.away?(node)

        infer[node].add_downstream(ctx, infer, use_pos, info, aliases)
      end
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      clauses.each do |node|
        next if infer.jumps.away?(node)

        infer[node].within_domain!(ctx, infer, use_pos, constraint_pos, constraint, aliases)
      end
    end
  end

  class TypeParamCondition < DownstreamableInfo
    getter bool : MetaType # TODO: avoid needing the caller to supply this
    getter refine : Refer::TypeParam
    getter refine_type : MetaType

    def describe_kind; "type parameter condition" end

    def initialize(@pos, @bool, @refine, @refine_type)
      raise "#{@bool.show_type} is not Bool" unless @bool.show_type == "Bool"
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @bool
      .tap { |mt| within_downstream_constraints!(ctx, infer, mt) }
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, @bool, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class TypeCondition < DownstreamableInfo
    getter bool : MetaType # TODO: avoid needing the caller to supply this
    getter refine : AST::Node
    getter refine_type : MetaType

    def describe_kind; "type condition" end

    def initialize(@pos, @bool, @refine, @refine_type)
      raise "#{@bool.show_type} is not Bool" unless @bool.show_type == "Bool"
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @bool
      .tap { |mt| within_downstream_constraints!(ctx, infer, mt) }
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, @bool, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class TrueCondition < DownstreamableInfo # TODO: dedup with FalseCondition?
    getter bool : MetaType # TODO: avoid needing the caller to supply this

    def describe_kind; "True value" end

    def initialize(@pos, @bool)
      raise "#{@bool.show_type} is not Bool" unless @bool.show_type == "Bool"
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @bool
      .tap { |mt| within_downstream_constraints!(ctx, infer, mt) }
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, @bool, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class FalseCondition < DownstreamableInfo # TODO: dedup with TrueCondition?
    getter bool : MetaType # TODO: avoid needing the caller to supply this

    def describe_kind; "False value" end

    def initialize(@pos, @bool)
      raise "#{@bool.show_type} is not Bool" unless @bool.show_type == "Bool"
    end

    def resolve!(ctx : Context, infer : ForFunc)
      @bool
      .tap { |mt| within_downstream_constraints!(ctx, infer, mt) }
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, @bool, use_pos, constraint_pos, constraint, aliases)
    end
  end

  class Refinement < DownstreamableInfo
    getter refine : AST::Node
    getter refine_type : MetaType

    def describe_kind; "type refinement" end

    def initialize(@pos, @refine, @refine_type)
    end

    def resolve!(ctx : Context, infer : ForFunc)
      infer[@refine].resolve!(ctx, infer).intersect(@refine_type)
      .tap { |mt| within_downstream_constraints!(ctx, infer, mt) }
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      meta_type_within_domain!(ctx, resolve!(ctx, infer), use_pos, constraint_pos, constraint, aliases)
    end
  end

  class Consume < DownstreamableInfo
    getter local : AST::Node

    def describe_kind; "consumed reference" end

    def initialize(@pos, @local)
    end

    def resolve!(ctx : Context, infer : ForFunc)
      infer[@local].resolve!(ctx, infer).ephemeralize
    end

    def add_downstream(ctx : Context, infer : ForFunc, use_pos : Source::Pos, info : Info, aliases : Int32)
      infer[@local].add_downstream(ctx, infer, use_pos, info, aliases - 1)
    end

    def within_domain!(ctx : Context, infer : ForFunc, use_pos : Source::Pos, constraint_pos : Source::Pos, constraint : MetaType, aliases : Int32)
      infer[@local].within_domain!(ctx, infer, use_pos, constraint_pos, constraint, aliases - 1)
    end
  end

  class FromYield < NamedInfo
    def describe_kind; "yield block result" end
  end

  class ArrayLiteral < DynamicInfo
    getter terms : Array(AST::Node)

    def initialize(@pos, @terms)
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

    def after_add_downstream(ctx : Context, infer : ForFunc, use_pos : Source::Pos, info : Info, aliases : Int32)
      antecedents = possible_element_antecedents(ctx, infer)
      return if antecedents.empty?

      terms.each do |term|
        # TODO: switch to add_downstream?
        infer[term].within_domain!(
          ctx,
          infer,
          (domain_constraints[0]?.try(&.[0]) || downstream_use_pos),
          (domain_constraints[0]?.try(&.[1]) || @downstreams.first[1].pos),
          MetaType.new_union(antecedents),
          0,
        )
      end
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

      total_domain_constraint(ctx).intersect(total_downstream_constraint(ctx, infer)).each_reachable_defn.to_a.each do |rt|
        # TODO: Support more element antecedent detection patterns.
        if rt.link == infer.prelude_type("Array") \
        && rt.args.size == 1
          results << rt.args.first
        end
      end

      results
    end
  end

  class FromCall < DynamicInfo
    getter lhs : AST::Node
    getter member : String
    getter args_pos : Array(Source::Pos)
    getter args : Array(AST::Node)
    getter yield_params : AST::Group?
    getter yield_block : AST::Group?
    getter ret_value_used : Bool
    @ret : MetaType?
    @ret_pos : Source::Pos? # TODO: remove?

    def initialize(@pos, @lhs, @member, @args, @args_pos, @yield_params, @yield_block, @ret_value_used)
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

    def follow_call_get_call_defns(ctx : Context, infer : ForFunc)
      call = self
      receiver = infer[call.lhs].resolve!(ctx, infer)
      call_defns = receiver.find_callable_func_defns(ctx, infer, call.member)

      # Raise an error if we don't have a callable function for every possibility.
      call_defns << {receiver.inner, nil, nil} if call_defns.empty?
      problems = [] of {Source::Pos, String}
      call_defns.each do |(call_mti, call_defn, call_func)|
        if call_defn.nil?
          problems << {call.pos,
            "the type #{call_mti.inspect} has no referencable types in it"}
        elsif call_func.nil?
          call_defn_defn = call_defn.defn(ctx)

          problems << {call_defn_defn.ident.pos,
            "#{call_defn_defn.ident.value} has no '#{call.member}' function"}

          found_similar = false
          if call.member.ends_with?("!")
            call_defn_defn.find_func?(call.member[0...-1]).try do |similar|
              found_similar = true
              problems << {similar.ident.pos,
                "maybe you meant to call '#{similar.ident.value}' (without '!')"}
            end
          else
            call_defn_defn.find_func?("#{call.member}!").try do |similar|
              found_similar = true
              problems << {similar.ident.pos,
                "maybe you meant to call '#{similar.ident.value}' (with a '!')"}
            end
          end

          unless found_similar
            similar = call_defn_defn.find_similar_function(call.member)
            problems << {similar.ident.pos,
              "maybe you meant to call the '#{similar.ident.value}' function"} \
                if similar
          end
        end
      end
      Error.at call,
        "The '#{call.member}' function can't be called on #{receiver.show_type}",
          problems unless problems.empty?

      call_defns
    end

    def follow_call_check_receiver_cap(ctx : Context, infer : ForFunc, call_mt, call_func, problems)
      call = self
      call_cap_mt = call_mt.cap_only
      autorecover_needed = false

      call_func_cap = MetaType::Capability.new_maybe_generic(call_func.cap.value)
      call_func_cap_mt = MetaType.new(call_func_cap)

      # The required capability is the receiver capability of the function,
      # unless it is an asynchronous function, in which case it is tag.
      required_cap = call_func_cap
      required_cap = MetaType::Capability.new("tag") \
        if call_func.has_tag?(:async) && !call_func.has_tag?(:constructor)

      receiver_okay =
        if required_cap.value.is_a?(String)
          call_cap_mt.subtype_of?(ctx, MetaType.new(required_cap))
        else
          call_cap_mt.satisfies_bound?(ctx, MetaType.new(required_cap))
        end

      # Enforce the capability restriction of the receiver.
      if receiver_okay
        # For box functions only, we reify with the actual cap on the caller side.
        # Or rather, we use "ref", "box", or "val", depending on the caller cap.
        # For all other functions, we just use the cap from the func definition.
        reify_cap =
          if required_cap.value == "box"
            case call_cap_mt.inner.as(MetaType::Capability).value
            when "iso", "trn", "ref" then MetaType.cap("ref")
            when "val" then MetaType.cap("val")
            else MetaType.cap("box")
            end
          # TODO: This shouldn't be a special case - any generic cap should be accepted.
          elsif required_cap.value.is_a?(Set(MetaType::Capability))
            call_cap_mt
          else
            call_func_cap_mt
          end
      elsif call_func.has_tag?(:constructor)
        # Constructor calls ignore cap of the original receiver.
        reify_cap = call_func_cap_mt
      elsif call_cap_mt.ephemeralize.subtype_of?(ctx, MetaType.new(required_cap))
        # We failed, but we may be able to use auto-recovery.
        # Take note of this and we'll finish the auto-recovery checks later.
        autorecover_needed = true
        # For auto-recovered calls, always use the cap of the func definition.
        reify_cap = call_func_cap_mt
      else
        # We failed entirely; note the problem and carry on.
        problems << {call_func.cap.pos,
          "the type #{call_mt.inner.inspect} isn't a subtype of the " \
          "required capability of '#{required_cap}'"}

        # If the receiver of the call is the self (the receiver of the caller),
        # then we can give an extra hint about changing its capability to match.
        if infer[call.lhs].is_a?(Self)
          problems << {infer.func.cap.pos, "this would be possible if the " \
            "calling function were declared as `:fun #{required_cap}`"}
        end

        # We already failed subtyping for the receiver cap, but pretend
        # for now that we didn't for the sake of further checks.
        reify_cap = call_func_cap_mt
      end

      {required_cap, reify_cap, autorecover_needed}
    end

    def follow_call_check_args(ctx : Context, infer : ForFunc, call_func, other_infer, problems)
      call = self

      # First, check the number of arguments.
      max = other_infer.params.size
      min = other_infer.params.count { |param| !AST::Extract.param(param)[2] }
      func_pos = call_func.ident.pos
      if call.args.size > max
        args = max == 1 ? "argument" : "arguments"
        params_pos = call_func.params.try(&.pos) || call_func.ident.pos
        problems << {call.pos, "the call site has too many arguments"}
        problems << {params_pos, "the function allows at most #{max} #{args}"}
        return
      elsif call.args.size < min
        args = min == 1 ? "argument" : "arguments"
        params_pos = call_func.params.try(&.pos) || call_func.ident.pos
        problems << {call.pos, "the call site has too few arguments"}
        problems << {params_pos, "the function requires at least #{min} #{args}"}
        return
      end

      # Apply parameter constraints to each of the argument types.
      # TODO: handle case where number of args differs from number of params.
      # TODO: enforce that all call_defns have the same param count.
      unless call.args.empty?
        call.args.zip(other_infer.params).zip(call.args_pos).each do |(arg, param), arg_pos|
          other_infer[param].as(Param).verify_arg(ctx, other_infer, infer, arg, arg_pos)
        end
      end
    end

    def follow_call_check_yield_block(other_infer, problems)
      if other_infer.yield_out_infos.empty?
        if yield_block
          problems << {yield_block.not_nil!.pos, "it has a yield block " \
            "but the called function does not have any yields"}
        end
      elsif !yield_block
        problems << {other_infer.yield_out_infos.first.first_viable_constraint_pos,
          "it has no yield block but the called function does yield"}
      end
    end

    def follow_call_check_autorecover_cap(ctx, infer, required_cap, call_func, other_infer, inferred_ret)
      call = self

      # If autorecover of the receiver cap was needed to make this call work,
      # we now have to confirm that arguments and return value are all sendable.
      problems = [] of {Source::Pos, String}

      unless required_cap.value == "ref" || required_cap.value == "box"
        problems << {call_func.cap.pos,
          "the function's receiver capability is `#{required_cap}` " \
          "but only a `ref` or `box` receiver can be auto-recovered"}
      end

      unless inferred_ret.is_sendable? || !call.ret_value_used
        problems << {other_infer.ret.pos,
          "the return type #{inferred_ret.show_type} isn't sendable " \
          "and the return value is used (the return type wouldn't matter " \
          "if the calling side entirely ignored the return value"}
      end

      # TODO: It should be safe to pass in a TRN if the receiver is TRN,
      # so is_sendable? isn't quite liberal enough to allow all valid cases.
      call.args.each do |arg|
        inferred_arg = infer[arg].resolve!(ctx, infer)
        unless inferred_arg.alias.is_sendable?
          problems << {arg.pos,
            "the argument (when aliased) has a type of " \
            "#{inferred_arg.alias.show_type}, which isn't sendable"}
        end
      end

      Error.at call,
        "This function call won't work unless the receiver is ephemeral; " \
        "it must either be consumed or be allowed to be auto-recovered. "\
        "Auto-recovery didn't work for these reasons",
          problems unless problems.empty?
    end

    def follow_call(ctx : Context, infer : ForFunc)
      call = self
      call_defns = follow_call_get_call_defns(ctx, infer)

      # For each receiver type definition that is possible, track down the infer
      # for the function that we're trying to call, evaluating the constraints
      # for each possibility such that all of them must hold true.
      rets = [] of MetaType
      poss = [] of Source::Pos
      problems = [] of {Source::Pos, String}
      call_defns.each do |(call_mti, call_defn, call_func)|
        call_mt = MetaType.new(call_mti)
        call_defn = call_defn.not_nil!
        call_func = call_func.not_nil!
        call_func_link = call_func.make_link(call_defn.link)

        # Keep track that we called this function.
        infer.analysis.called_funcs.add({call.pos, call_defn, call_func_link})

        required_cap, reify_cap, autorecover_needed =
          follow_call_check_receiver_cap(ctx, infer, call_mt, call_func, problems)

        # Get the ForFunc instance for call_func, possibly creating and running it.
        # TODO: don't infer anything in the body of that func if type and params
        # were explicitly specified in the function signature.
        other_infer = ctx.infer.for_func(ctx, call_defn, call_func_link, reify_cap).tap(&.run)

        follow_call_check_args(ctx, infer, call_func, other_infer, problems)
        follow_call_check_yield_block(other_infer, problems)

        # Resolve and take note of the return type.
        inferred_ret_info = other_infer[other_infer.ret]
        inferred_ret = inferred_ret_info.resolve!(ctx, other_infer)
        rets << inferred_ret
        poss << inferred_ret_info.pos

        if autorecover_needed
          follow_call_check_autorecover_cap(ctx, infer, required_cap, call_func, other_infer, inferred_ret)
        end
      end
      Error.at call,
        "This function call doesn't meet subtyping requirements",
          problems unless problems.empty?

      # Constrain the return value as the union of all observed return types.
      ret = rets.size == 1 ? rets.first : MetaType.new_union(rets)
      pos = poss.size == 1 ? poss.first : call.pos

      call.set_return(infer, pos, ret)
    end

    def visit_and_verify_yield_block(ctx : Context, infer : ForFunc, yield_params, yield_block)
      return unless yield_block

      call_defns = follow_call_get_call_defns(ctx, infer)

      # TODO: Because we visit yield_params and yield_block, we'll have
      # problems with multiple call defns because we'll end up with potentially
      # conflicting information gathered each time. Somehow, we need to be able
      # to iterate over it multiple times and type-assign them separately,
      # so that specialized code can be generated for each different receiver
      # that may have different types. This is totally nontrivial...
      raise NotImplementedError.new("yield_block with multiple call_defns") \
        if yield_block && call_defns.size > 1

      call_defns.each do |(call_mti, call_defn, call_func)|
        call_mt = MetaType.new(call_mti)
        call_defn = call_defn.not_nil!
        call_func = call_func.not_nil!
        call_func_link = call_func.make_link(call_defn.link)

        problems = [] of {Source::Pos, String}
        required_cap, reify_cap, autorecover_needed =
          follow_call_check_receiver_cap(ctx, infer, call_mt, call_func, problems)
        raise "this should have been prevented earlier" if problems.any?

        other_infer = ctx.infer.for_func(ctx, call_defn, call_func_link, reify_cap).tap(&.run)

        # Based on the resolved function, assign the proper yield param types.
        if yield_params
          raise "TODO: Nice error message for this" \
            if other_infer.yield_out_infos.size != yield_params.terms.size

          other_infer.yield_out_infos.zip(yield_params.terms)
          .each do |yield_out, yield_param|
            # TODO: Use .assign instead of .set_explicit after figuring out how to have an AST node for it
            infer[yield_param].as(Local).set_explicit(
              yield_out.first_viable_constraint_pos,
              yield_out.resolve!(ctx, other_infer),
            )
          end
        end

        # Now visit the yield block to register them in our state.
        # We must do this after the lines above where the params were handled.
        # Note that we skipped it before with visit_children: false.
        yield_block.try(&.accept(ctx, infer))

        # Finally, check that the type of the result of the yield block,
        # but don't bother if it has a type requirement of None.
        yield_in_resolved = other_infer.analysis.yield_in_resolved
        none = MetaType.new(infer.reified_type(infer.prelude_type("None")))
        if yield_in_resolved != none
          infer[yield_block].within_domain!(
            ctx,
            infer,
            yield_block.pos,
            other_infer.yield_in_info.pos,
            other_infer.yield_in_info.resolve!(ctx, other_infer),
            0,
          )
        end
      end
    end
  end
end
