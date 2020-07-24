class Mare::Compiler::Infer
  struct Tether
    def initialize(@info : Info, @below : StructRef(Tether)? = nil)
    end

    def self.via(info : Info, list : Array(Tether))
      list.map { |below| new(info, StructRef(Tether).new(below)) }
    end

    def root : Info
      below = @below
      below ? below.root : @info
    end

    def to_a : Array(Info)
      below = @below
      below ? below.to_a.tap(&.push(@info)) : [@info]
    end

    def constraint(ctx : Context, infer : ForReifiedFunc, immediate : Bool = false) : MetaType
      below = @below
      if below
        if immediate
          below.constraint(ctx, infer)
        else
          @info.tether_upward_transform(ctx, infer, below.constraint(ctx, infer))
        end
      else
        @info.tether_resolve(ctx, infer)
      end
    end

    def includes?(other_info) : Bool
      @info == other_info || @below.try(&.includes?(other_info)) || false
    end
  end

  abstract class Info
    property pos : Source::Pos = Source::Pos.none
    property override_describe_kind : String?

    abstract def add_downstream(use_pos : Source::Pos, info : Info, aliases : Int32)

    abstract def tethers(querent : Info) : Array(Tether)
    def tether_upward_transform(ctx : Context, infer : ForReifiedFunc, meta_type : MetaType) : MetaType
      raise NotImplementedError.new("tether_upward_transform for #{self.class}:\n#{pos.show}")
    end
    def tether_resolve(ctx : Context, infer : ForReifiedFunc)
      raise NotImplementedError.new("tether_resolve for #{self.class}:\n#{pos.show}")
    end

    # Most Info types ignore hints, but a few override this method to see them,
    # or to pass them along to other nodes that may wish to see them.
    def add_peer_hint(peer : Info)
    end

    abstract def resolve!(ctx : Context, infer : ForReifiedFunc) : MetaType
    def post_resolve!(ctx : Context, infer : ForReifiedFunc, mt : MetaType)
    end

    # For Info types which represent a tree of Info nodes, they should override
    # this method to resolve everything in their tree.
    def resolve_others!(ctx : Context, infer : ForReifiedFunc)
    end

    # In the rare case that an Info subclass needs to dynamically pretend to be
    # a different downstream constraint, it can override this method.
    # If you need to report multiple positions, also override the other method
    # below called as_multiple_downstream_constraints.
    # This will prevent upstream DynamicInfos from eagerly resolving you.
    def as_downstream_constraint_meta_type(ctx : Context, infer : ForReifiedFunc) : MetaType?
      infer.resolve(ctx, self)
    end

    # In the rare case that an Info subclass needs to dynamically pretend to be
    # multiple different downstream constraints, it can override this method.
    # This is only used to report positions in more detail, and it is expected
    # that the intersection of all MetaTypes here is the same as the resolve.
    def as_multiple_downstream_constraints(ctx : Context, infer : ForReifiedFunc) : Array({Source::Pos, MetaType})?
      nil
    end

    # TODO: remove this cheap hacky alias somehow:
    def as_multiple_downstream_constraints(ctx : Context, analysis : ReifiedFuncAnalysis) : Array({Source::Pos, MetaType})?
      infer = ctx.infer.for_rf_existing!(analysis.reified)
      as_multiple_downstream_constraints(ctx, infer)
    end
  end

  abstract class DynamicInfo < Info
    # Must be implemented by the child class as an required hook.
    abstract def describe_kind : String

    def described_kind
      override_describe_kind || describe_kind
    end

    # May be implemented by the child class as an optional hook.
    def adds_alias; 0 end

    # Values flow downstream as the program executes;
    # the value flowing into a downstream must be a subtype of the downstream.
    # Type information can be inferred in either direction, but certain
    # Info node types are fixed, meaning that they act only as constraints
    # on their upstreams, and are not influenced at all by upstream info nodes.
    @downstreams = [] of Tuple(Source::Pos, Info, Int32)
    def add_downstream(use_pos : Source::Pos, info : Info, aliases : Int32)
      @downstreams << {use_pos, info, aliases + adds_alias}
      after_add_downstream(use_pos, info, aliases)
    end
    def downstreams_empty?
      @downstreams.empty?
    end
    def downstream_use_pos
      @downstreams.first[0]
    end

    # May be implemented by the child class as an optional hook.
    def after_add_downstream(use_pos : Source::Pos, info : Info, aliases : Int32)
    end

    def tethers(querent : Info) : Array(Tether)
      @downstreams.flat_map do |pos, info, aliases|
        next [] of Tether if querent == info
        Tether.via(self, info.tethers(querent))
      end
    end

    def tether_constraints(ctx : Context, infer : ForReifiedFunc)
      tethers(self).map(&.constraint(ctx, infer, true).as(MetaType))
    end

    def describe_tether_constraints(ctx : Context, infer : ForReifiedFunc)
      tethers(self).map do |tether|
        mt = tether.constraint(ctx, infer, true)
        {tether.root.pos,
          "it is required here to be a subtype of #{mt.show_type}"}
      end
    end

    # When we need to take into consideration the downstreams' constraints
    # in order to infer our type from them, we can use this to collect all
    # those constraints into one intersection of them all.
    def total_downstream_constraint(ctx : Context, infer : ForReifiedFunc)
      MetaType.new_intersection(
        @downstreams.map do |_, other_info, _|
          other_info.as_downstream_constraint_meta_type(ctx, infer).as(MetaType)
        end
      )
    end

    # TODO: remove?
    def describe_downstream_constraints(ctx : Context, infer : ForReifiedFunc)
      @downstreams.flat_map do |_, other_info, _|
        multi = other_info.as_multiple_downstream_constraints(ctx, infer)
        if multi
          multi.map do |other_info_pos, mt|
            {other_info_pos,
              "it is required here to be a subtype of #{mt.show_type}"}
          end
        else
          mt = infer.resolve(ctx, other_info)
          [{other_info.pos,
            "it is required here to be a subtype of #{mt.show_type}"}]
        end
      end.to_h.to_a
    end

    # TODO: document
    def within_downstream_constraints!(ctx : Context, infer : ForReifiedFunc, meta_type : MetaType)
      if !within_downstream_constraints?(ctx, infer, meta_type)
        extra = describe_downstream_constraints(ctx, infer)
        extra << {pos,
          "but the type of the #{described_kind} was #{meta_type.show_type}"}

        Error.at downstream_use_pos, "The type of this expression " \
          "doesn't meet the constraints imposed on it",
            extra
      end
    end
    def within_downstream_constraints?(ctx : Context, infer : ForReifiedFunc, meta_type : MetaType)
      return true if @downstreams.empty?
      meta_type.within_constraints?(ctx, [total_downstream_constraint(ctx, infer)])
    end

    # This property can be set to give a hint in the event of a typecheck error.
    property this_would_be_possible_if : Tuple(Source::Pos, String)?

    # The final MetaType must meet all constraints that have been imposed.
    def post_resolve!(ctx : Context, infer : ForReifiedFunc, meta_type : MetaType)
      return if downstreams_empty?

      # TODO: print a different error message when the downstream constraints are
      # internally conflicting, even before adding this meta_type into the mix.

      if !meta_type.ephemeralize.within_constraints?(ctx, [total_downstream_constraint(ctx, infer)])
        extra = describe_downstream_constraints(ctx, infer)
        extra << {pos,
          "but the type of the #{described_kind} was #{meta_type.show_type}"}
        extra << this_would_be_possible_if.not_nil! if this_would_be_possible_if

        Error.at downstream_use_pos, "The type of this expression " \
          "doesn't meet the constraints imposed on it",
            extra
      end

      # If aliasing makes a difference, we need to evaluate each constraint
      # that has nonzero aliases with an aliased version of the meta_type.
      if meta_type != meta_type.strip_ephemeral.alias
        meta_type_alias = meta_type.strip_ephemeral.alias

        # TODO: Do we need to do anything here to weed out union types with
        # differing capabilities of compatible terms? Is it possible that
        # the type that fulfills the total_downstream_constraint is not compatible
        # with the ephemerality requirement, while some other union member is?
        @downstreams.each do |use_pos, other_info, aliases|
          if aliases > 0
            constraint = infer.resolve(ctx, other_info)
            if !meta_type_alias.within_constraints?(ctx, [constraint])
              extra = describe_downstream_constraints(ctx, infer)
              extra << {pos,
                "but the type of the #{described_kind} " \
                "(when aliased) was #{meta_type_alias.show_type}"
              }
              extra << this_would_be_possible_if.not_nil! if this_would_be_possible_if

              Error.at use_pos, "This aliasing violates uniqueness " \
                "(did you forget to consume the variable?)",
                extra
            end
          end
        end
      end
    end
  end

  abstract class NamedInfo < DynamicInfo
    @explicit : Info?
    @upstreams = [] of Tuple(Info, Source::Pos)

    def initialize(@pos)
    end

    def adds_alias; 1 end

    def first_viable_constraint_pos : Source::Pos
      (downstream_use_pos unless downstreams_empty?)
      @upstreams[0]?.try(&.[1]) ||
      @pos
    end

    def explicit? : Bool
      !!@explicit
    end

    def set_explicit(explicit : Info)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" unless @upstreams.empty?

      @explicit = explicit
      @pos = explicit.pos
    end

    def tethers(querent : Info) : Array(Tether)
      results = [] of Tether
      results.concat(@explicit.not_nil!.tethers(querent)) if @explicit && querent != @explicit
      @downstreams.each do |pos, info, aliases|
        results.concat(Tether.via(self, info.tethers(querent))) if querent != info
      end
      results
    end

    def after_add_downstream(use_pos : Source::Pos, info : Info, aliases : Int32)
      return if @explicit

      @upstreams.each do |upstream, upstream_pos|
        upstream.add_downstream(use_pos, info, aliases)
      end
    end

    def tether_upward_transform(ctx : Context, infer : ForReifiedFunc, meta_type : MetaType) : MetaType
      # TODO: aliasing/ephemerality
      meta_type
    end

    def assign(ctx : Context, upstream : Info, upstream_pos : Source::Pos)
      @upstreams << {upstream, upstream_pos}

      if @explicit
        upstream.add_downstream(upstream_pos, @explicit.not_nil!, 0)
      else
        upstream.add_downstream(upstream_pos, self, 0)
      end
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      explicit = @explicit

      if explicit
        explicit_mt = infer.resolve(ctx, explicit)

        if !explicit_mt.cap_only?
          # If we have an explicit type that is more than just a cap, return it.
          return explicit_mt
        elsif !@upstreams.empty?
          # If there are upstreams, use the explicit cap applied to the type
          # of the first upstream expression, which becomes canonical.
          return (
            infer.resolve(ctx, @upstreams.first[0])
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
        return infer.resolve(ctx, @upstreams.first[0]).strip_ephemeral
      elsif !downstreams_empty?
        # If we only have downstream tethers, just do our best with those.
        return MetaType
          .new_intersection(tether_constraints(ctx, infer))
          .simplify(ctx)
          .strip_ephemeral
      end

      # If we get here, we've failed and don't have enough info to continue.
      Error.at self,
        "This #{described_kind} needs an explicit type; it could not be inferred"
    end
  end

  abstract class FixedInfo < DynamicInfo # TODO: rename or split DynamicInfo to make this line make more sense
    def tethers(querent : Info) : Array(Tether)
      [Tether.new(self)]
    end

    def tether_resolve(ctx : Context, infer : ForReifiedFunc)
      infer.resolve(ctx, self)
    end
  end

  class FixedPrelude < FixedInfo
    getter name : String
    getter resolvables : Array(Info)

    def describe_kind; "expression" end

    def initialize(@pos, @name)
      @resolvables = [] of Info
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      MetaType.new(infer.reified_type(infer.prelude_type(@name)))
    end

    def resolve_others!(ctx : Context, infer : ForReifiedFunc)
      @resolvables.each { |resolvable| infer.resolve(ctx, resolvable) }
    end
  end

  class FixedTypeExpr < FixedInfo
    getter node : AST::Node

    def describe_kind; "type expression" end

    def initialize(@pos, @node)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      infer.type_expr(@node)
    end
  end

  class FixedEnumValue < FixedInfo
    getter node : AST::Node

    def describe_kind; "expression" end

    def initialize(@pos, @node)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      infer.type_expr(@node)
    end
  end

  class FixedSingleton < FixedInfo
    getter node : AST::Node
    getter type_param_ref : Refer::TypeParam?

    def describe_kind; "singleton value for this type" end

    def initialize(@pos, @node, @type_param_ref = nil)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      # If this node is further qualified, we don't want to both resolving it,
      # and doing so would trigger errors during type argument validation,
      # because the type arguments haven't been applied yet; they will be
      # applied in a different FixedSingleton that wraps this one in range.
      # We don't have to resolve it because nothing will ever be its downstream.
      return MetaType.unsatisfiable if @node.is_a?(AST::Identifier) \
        && infer.classify.further_qualified?(@node)

      infer.type_expr(@node).override_cap("non")
      .tap { |mt| ctx.infer.validate_type_args(ctx, infer, @node, mt) }
    end
  end

  class Self < FixedInfo
    def describe_kind; "receiver value" end

    def initialize(@pos)
    end

    def downstream_constraints(ctx : Context, analysis : ReifiedFuncAnalysis)
      @downstreams.flat_map do |_, info, _|
        info.as_multiple_downstream_constraints(ctx, analysis) \
        || [{info.pos, analysis.resolved(info)}]
      end
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      infer.analysis.resolved_self
    end
  end

  class FromConstructor < FixedInfo
    def describe_kind; "constructed object" end

    def initialize(@pos, @cap : String)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      # A constructor returns the ephemeral of the self type with the given cap.
      # TODO: should the ephemeral be removed, given Mare's ephemeral semantics?
      MetaType.new(infer.reified.type, @cap).ephemeralize
    end
  end

  class ReflectionOfType < DynamicInfo
    getter reflect_type : Info

    def describe_kind; "type reflection" end

    def initialize(@pos, @reflect_type)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      follow_reflection(ctx, infer)
    end

    def follow_reflection(ctx : Context, infer : ForReifiedFunc)
      reflect_mt = infer.for_rt.resolve_type_param_parent_links(infer.resolve(ctx, @reflect_type))
      reflect_rt =
        if reflect_mt.type_params.empty?
          reflect_mt.single!
        else
          # If trying to reflect a type with unreified type params in it,
          # we just shrug and reflect the type None instead, since it doesn't
          # seem like there is anything more meaningful we could do here.
          # This happens when typechecking on not-yet-reified functions,
          # so it isn't really avoidable. But it shouldn't reach CodeGen.
          infer.reified_type(infer.prelude_type("None"))
        end

      # Reach all functions that might possibly be reflected.
      reflect_rt.defn(ctx).functions.each do |f|
        next if f.has_tag?(:hygienic) || f.body.nil?
        f_link = f.make_link(reflect_rt.link)
        MetaType::Capability.new_maybe_generic(f.cap.value).each_cap.each do |f_cap|
          ctx.infer.for_rf(ctx, reflect_rt, f_link, MetaType.new(f_cap)).tap(&.run)
        end
        infer.extra_called_func!(@pos, reflect_rt, f_link)
      end

      MetaType.new(infer.reified_type(infer.prelude_type("ReflectionOfType"), [reflect_mt]))
    end

  end

  class Literal < DynamicInfo
    def describe_kind; "literal value" end

    def initialize(@pos, @possible : MetaType)
      @peer_hints = [] of Info
    end

    def add_peer_hint(peer : Info)
      @peer_hints << peer
    end

    def describe_peer_hints(ctx : Context, infer : ForReifiedFunc)
      @peer_hints.map do |peer|
        mt = infer.resolve(ctx, peer)
        {peer.pos, "it is suggested here that it might be a #{mt.show_type}"}
      end
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      tether_constraints = tether_constraints(ctx, infer)

      # Literal values (such as numeric literals) sometimes have
      # an ambiguous type. Here, we intersect with the downstream constraints
      # to (hopefully) arrive at a single concrete type to return.
      meta_type = MetaType
        .new_intersection(tether_constraints + [@possible])
        .simplify(ctx)

      # If we don't satisfy the constraints, leave it to DynamicInfo.resolve!
      # to print a consistent error message instead of printing it here.
      return @possible if meta_type.unsatisfiable?

      # If we've resolved to a single concrete type, we can successfully return.
      return meta_type if meta_type.singular? && meta_type.single!.link.is_concrete?

      # Next we try to use peer hints to make a viable guess.
      if @peer_hints.any?
        meta_type = MetaType.new_intersection(
          @peer_hints.map { |peer| infer.resolve(ctx, peer).as(MetaType) }
        ).intersect(@possible).simplify(ctx)

        # This guess works for us if it meets those same criteria from before.
        return meta_type if meta_type.singular? && meta_type.single!.link.is_concrete?
      end

      # We've failed on all fronts. Print an error describing what we know,
      # so that the user can figure out how to give us better information.
      error_info = describe_tether_constraints(ctx, infer)
      error_info.concat(describe_peer_hints(ctx, infer))
      error_info.push({pos,
        "and the literal itself has an intrinsic type of #{@possible.show_type}"
      })
      error_info.push({Source::Pos.none,
        "Please wrap an explicit numeric type around the literal " \
          "(for example: U64[#{@pos.content}])"
      })
      Error.at self,
        "This literal value couldn't be inferred as a single concrete type",
        error_info

      raise "unreachable end of function"
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
  end

  class Field < DynamicInfo
    def initialize(@pos, @name : String)
      @upstreams = [] of Info
    end

    def describe_kind; "field reference" end

    def assign(ctx : Context, upstream : Info, upstream_pos : Source::Pos)
      upstream.add_downstream(upstream_pos, self, 0)
      @upstreams << upstream
    end

    def tethers(querent : Info) : Array(Tether)
      [Tether.new(self)]
    end

    def tether_resolve(ctx : Context, infer : ForReifiedFunc)
      infer.resolve(ctx, self)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      follow_field(ctx, infer)
    end

    def resolve_others!(ctx : Context, infer : ForReifiedFunc)
      @upstreams.each { |upstream| infer.resolve(ctx, upstream) }
    end

    def follow_field(ctx : Context, infer : ForReifiedFunc) : MetaType
      field_func = infer.reified.type.defn(ctx).functions.find do |f|
        f.ident.value == @name && f.has_tag?(:field)
      end.not_nil!
      field_func_link = field_func.make_link(infer.reified.type.link)

      # Keep track that we touched this "function".
      infer.analysis.called_funcs.add({pos, infer.reified.type, field_func_link})

      # Get the ForReifiedFunc instance for field_func, possibly creating and running it.
      other_infer = ctx.infer.for_rf(ctx, infer.reified.type, field_func_link, infer.analysis.resolved_self_cap).tap(&.run)

      # Get the return type.
      other_infer.resolve(ctx, other_infer.f_analysis[other_infer.ret])
    end
  end

  class FieldRead < DynamicInfo
    def initialize(@field : Field, @origin : Self)
    end

    def describe_kind; "field read" end

    def pos
      @field.pos
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      origin_mt = infer.resolve(ctx, @origin)
      field_mt = infer.resolve(ctx, @field)
      field_mt.viewed_from(origin_mt).alias
    end
  end

  class FieldExtract < DynamicInfo
    def initialize(@field : Field, @origin : Self)
    end

    def describe_kind; "field extraction" end

    def pos
      @field.pos
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      origin_mt = infer.resolve(ctx, @origin)
      field_mt = infer.resolve(ctx, @field)
      field_mt.extracted_from(origin_mt).ephemeralize
    end
  end

  class RaiseError < Info
    def initialize(@pos)
    end

    def add_downstream(use_pos : Source::Pos, info : Info, aliases : Int32)
      raise "can't be downstream of a RaiseError"
    end

    def tethers(querent : Info) : Array(Tether)
      [] of Tether
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      MetaType.new(MetaType::Unsatisfiable.instance)
    end
  end

  class Sequence < Info
    getter terms : Array(Info)
    getter final_term : Info

    def initialize(pos, @terms)
      @final_term = @terms.empty? ? FixedPrelude.new(pos, "None") : @terms.last
      @pos = @final_term.pos
    end

    def add_downstream(use_pos : Source::Pos, info : Info, aliases : Int32)
      final_term.add_downstream(use_pos, info, aliases)
    end

    def tethers(querent : Info) : Array(Tether)
      final_term.tethers(querent)
    end

    def add_peer_hint(peer : Info)
      final_term.add_peer_hint(peer)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      infer.resolve(ctx, final_term)
    end

    def resolve_others!(ctx : Context, infer : ForReifiedFunc)
      terms.each { |term| infer.resolve(ctx, term) }
    end
  end

  # TODO: add some kind of logic for analyzing exhausted choices,
  # as well as necessary/sufficient conditions for each branch to be in play
  # letting us better specialize the codegen later by eliminating impossible
  # branches in particular reifications of this type or function.
  class Phi < DynamicInfo
    getter branches : Array({Info?, Info, Bool})

    def describe_kind; "choice block" end

    def initialize(@pos, @branches)
      prior_bodies = [] of Info

      @branches.each do |cond, body, body_jumps_away|
        next if body_jumps_away
        body.add_downstream(@pos, self, 0)
        prior_bodies.each { |prior_body| body.add_peer_hint(prior_body) }
        prior_bodies << body
      end
    end

    def tether_upward_transform(ctx : Context, infer : ForReifiedFunc, meta_type : MetaType) : MetaType
      # TODO: account for unreachable branches? maybe? maybe not?
      meta_type
    end

    def as_downstream_constraint_meta_type(ctx : Context, infer : ForReifiedFunc) : MetaType?
      total_downstream_constraint(ctx, infer)
    end

    def as_multiple_downstream_constraints(ctx : Context, infer : ForReifiedFunc) : Array({Source::Pos, MetaType})?
      @downstreams.map do |pos, info, aliases|
        {pos, info.as_downstream_constraint_meta_type(ctx, infer)}
      end
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      MetaType.new_union(
        follow_branches(ctx, infer)
      )
    end

    def follow_branches(ctx : Context, infer : ForReifiedFunc)
      meta_types = [] of MetaType
      statically_true_conds = [] of Info
      branches.each do |cond, body, body_jumps_away|
        meta_type = follow_branch(ctx, infer, cond, body, statically_true_conds)
        meta_types << meta_type if meta_type && !body_jumps_away
        break unless statically_true_conds.empty?
      end

      meta_types
    end

    def follow_branch(
      ctx : Context,
      infer : ForReifiedFunc,
      cond : Info?,
      body : Info,
      statically_true_conds : Array(Info),
    )
      infer.resolve(ctx, cond) if cond
      return unless body

      inner_cond = cond
      while inner_cond.is_a?(Sequence)
        inner_cond = inner_cond.final_term
      end

      skip_body = false

      # If we have a type condition as the cond, that implies that it returned
      # true if we are in the body; hence we can apply the type refinement.
      # TODO: Do this in a less special-casey sort of way if possible.
      # TODO: Do we need to override things besides locals? should we skip for non-locals?
      if inner_cond.is_a?(TypeParamCondition)
        refine_type = infer.resolve(ctx, inner_cond.refine_type)

        infer.for_rt.push_type_param_refinement(
          inner_cond.refine,
          refine_type,
        )

        # When the type param is currently partially or fully reified with
        # a type that is incompatible with the refinement, we skip the body.
        current_type_param = infer.lookup_type_param(inner_cond.refine)
        if current_type_param.satisfies_bound?(ctx, refine_type)
          # TODO: this is one of the statically_true_conds as well, right?
        else
          skip_body = true
        end
      elsif inner_cond.is_a?(TypeConditionStatic)
        if inner_cond.evaluate(ctx, infer)
          # A statically true condition prevents all later branch bodies
          # from having a chance to be executed, since it happens first.
          statically_true_conds << inner_cond
        else
          # A statically false condition will not execute its branch body.
          skip_body = true
        end
      end

      # Resolve the types inside the body and capture the result type,
      # unless there is no body or we have determined we must skip this body.
      if body
        if skip_body
          # We use "unconstrained" as a marker that this is unreachable.
          infer.resolve_as(ctx, body, MetaType.unconstrained)
        else
          meta_type = infer.resolve(ctx, body)
        end
      end

      # Remove the type param refinement we put in place before, if any.
      if inner_cond.is_a?(TypeParamCondition)
        infer.for_rt.pop_type_param_refinement(inner_cond.refine)
      end

      meta_type
    end
  end

  class TypeParamCondition < FixedInfo
    getter refine : Refer::TypeParam
    getter lhs : Info
    getter refine_type : Info

    def describe_kind; "type parameter condition" end

    def initialize(@pos, @refine, @lhs, @refine_type)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      MetaType.new(infer.reified_type(infer.prelude_type("Bool")))
    end

    def resolve_others!(ctx : Context, infer : ForReifiedFunc)
      infer.resolve(ctx, @lhs)
      infer.resolve(ctx, @refine_type)
    end
  end

  class TypeCondition < FixedInfo
    getter lhs : Info
    getter rhs : Info

    def describe_kind; "type condition" end

    def initialize(@pos, @lhs, @rhs)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      MetaType.new(infer.reified_type(infer.prelude_type("Bool")))
    end

    def post_resolve!(ctx : Context, infer : ForReifiedFunc, meta_type : MetaType)
      super

      rhs_mt = infer.resolve(ctx, @rhs)
      lhs_mt = infer.resolve(ctx, @lhs)
      if !rhs_mt.subtype_of?(ctx, lhs_mt)
        Error.at @pos, "This type check will never match", [
          {@rhs.pos, "the match type is #{rhs_mt.show_type}"},
          {@lhs.pos, "which is not a subtype of #{lhs_mt.show_type}"},
        ]
      end
    end
  end

  class TypeConditionForLocal < FixedInfo
    getter refine : AST::Node
    getter refine_type : Info

    def describe_kind; "type condition" end

    def initialize(@pos, @refine, @refine_type)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      MetaType.new(infer.reified_type(infer.prelude_type("Bool")))
    end

    def post_resolve!(ctx : Context, infer : ForReifiedFunc, meta_type : MetaType)
      super

      lhs_info = infer.f_analysis[@refine].as(NamedInfo)
      rhs_mt = infer.resolve(ctx, @refine_type)
      lhs_mt = infer.resolve(ctx, lhs_info)
      if !rhs_mt.subtype_of?(ctx, lhs_mt)
        Error.at @pos, "This type check will never match", [
          {@refine_type.pos, "the match type is #{rhs_mt.show_type}"},
          {lhs_info.first_viable_constraint_pos,
            "which is not a subtype of #{lhs_mt.show_type}"},
        ]
      end
    end
  end

  class TypeConditionStatic < FixedInfo
    getter lhs : Info
    getter rhs : Info

    def describe_kind; "static type condition" end

    def initialize(@pos, @lhs, @rhs)
    end

    def evaluate(ctx : Context, infer : ForReifiedFunc) : Bool
      lhs_mt = infer.resolve(ctx, lhs)
      rhs_mt = infer.resolve(ctx, rhs)
      lhs_mt.satisfies_bound?(ctx, rhs_mt)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      MetaType.new(infer.reified_type(infer.prelude_type("Bool")))
    end
  end

  class Refinement < DynamicInfo
    getter refine : Info
    getter refine_type : Info

    def describe_kind; "type refinement" end

    def initialize(@pos, @refine, @refine_type)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      infer.resolve(ctx, @refine).intersect(infer.resolve(ctx, @refine_type))
    end
  end

  class Consume < Info
    getter local : Info

    def describe_kind; "consumed reference" end

    def initialize(@pos, @local)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      infer.resolve(ctx, @local).ephemeralize
    end

    def add_downstream(use_pos : Source::Pos, info : Info, aliases : Int32)
      @local.add_downstream(use_pos, info, aliases - 1)
    end

    def tethers(querent : Info) : Array(Tether)
      return [] of Tether if querent == @local
      Tether.via(self, @local.tethers(querent))
    end

    def add_peer_hint(peer : Info)
      @local.add_peer_hint(peer)
    end
  end

  class FromAssign < Info
    getter lhs : NamedInfo
    getter rhs : Info

    def describe_kind; "assign result" end

    def initialize(@pos, @lhs, @rhs)
    end

    def add_downstream(use_pos : Source::Pos, info : Info, aliases : Int32)
      @lhs.add_downstream(use_pos, info, aliases)
    end

    def tethers(querent : Info) : Array(Tether)
      return [] of Tether if querent == @lhs
      Tether.via(self, @lhs.tethers(querent))
    end

    def add_peer_hint(peer : Info)
      @lhs.add_peer_hint(peer)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      infer.resolve(ctx, @lhs).alias
    end

    def resolve_others!(ctx : Context, infer : ForReifiedFunc)
      infer.resolve(ctx, @rhs)
    end
  end

  class FromYield < Info
    getter yield_in : Info
    getter terms : Array(Info)

    def initialize(@pos, @yield_in, @terms)
    end

    def add_downstream(use_pos : Source::Pos, info : Info, aliases : Int32)
      @yield_in.add_downstream(use_pos, info, aliases)
    end

    def tethers(querent : Info) : Array(Tether)
      return [] of Tether if querent == @yield_in
      Tether.via(self, @yield_in.tethers(querent))
    end

    def add_peer_hint(peer : Info)
      @yield_in.add_peer_hint(peer)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      infer.resolve(ctx, @yield_in)
    end

    def resolve_others!(ctx : Context, infer : ForReifiedFunc)
      @terms.each { |term| infer.resolve(ctx, term) }
    end
  end

  class ArrayLiteral < DynamicInfo
    getter terms : Array(Info)

    def describe_kind; "array literal" end

    def initialize(@pos, @terms)
    end

    def after_add_downstream(use_pos : Source::Pos, info : Info, aliases : Int32)
      # Only do this after the first downstream is added.
      return unless @downstreams.size == 1

      elem_downstream = ArrayLiteralElementAntecedent.new(@downstreams.first[1].pos, self)
      @terms.each do |term|
        term.add_downstream(downstream_use_pos, elem_downstream, 0)
      end
    end

    def tether_upward_transform(ctx : Context, infer : ForReifiedFunc, meta_type : MetaType) : MetaType
      meta_type
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      array_defn = infer.prelude_type("Array")

      # By default, an array literal has a cap of `ref`.
      array_cap = MetaType::Capability::REF

      # Determine the lowest common denominator MetaType of all elements.
      elem_mts = terms.map { |term| infer.resolve(ctx, term).as(MetaType) }.uniq
      elem_mt = MetaType.new_union(elem_mts).simplify(ctx)
      orig_elem_mt_union = elem_mt

      # Look for exactly one antecedent type that matches the inferred type.
      # Essentially, this is the correlating "outside" inference with "inside".
      # If such a type is found, it replaces our inferred element type.
      # If no such type is found, stick with what we inferred for now.
      possible_antes = [] of {MetaType, MetaType::Capability}
      possible_element_antecedents(ctx, infer).each do |ante, cap|
        ante_simple = ante.simplify(ctx)
        if elem_mts.empty? || elem_mt.subtype_of?(ctx, ante_simple)
          possible_antes << {ante, cap}
        end
      end
      if possible_antes.size > 1
        # TODO: nice error for the below:
        raise "too many possible antecedents"
      elsif possible_antes.size == 1
        # We have a suitable antecedent, so we adopt the element type
        # as well as the associated capability for the array container type.
        elem_mt, array_cap = possible_antes.first
      else
        # Leave elem_mt alone and let it ride.
      end

      if elem_mt.unsatisfiable?
        Error.at pos,
          "The type of this empty array literal could not be inferred " \
          "(it needs an explicit type)"
      end

      # Now that we have the element type to use, construct the result.
      rt = infer.reified_type(infer.prelude_type(ctx, "Array"), [elem_mt])
      mt = MetaType.new(rt, array_cap.value.as(String))

      # If the array cap is not ref or "lesser", we must recover to the
      # higher capability, meaning all element expressions must be sendable.
      unless array_cap.supertype_of?(MetaType::Capability::REF)
        unless orig_elem_mt_union.alias.is_sendable?
          Error.at @pos, "This array literal can't have a reference cap of " \
            "#{array_cap.value} unless all of its elements are sendable",
              describe_tether_constraints(ctx, infer)
        end
      end

      # Reach the functions we will use during CodeGen.
      ["new", "<<"].each do |f_name|
        f = rt.defn(ctx).find_func!(f_name)
        f_link = f.make_link(rt.link)
        ctx.infer.for_rf(ctx, rt, f_link, MetaType.cap(f.cap.value)).run
        infer.extra_called_func!(pos, rt, f_link)
      end

      mt
    end

    def possible_element_antecedents(ctx, infer) : Array({MetaType, MetaType::Capability})
      results = [] of {MetaType, MetaType::Capability}

      MetaType
        .new_intersection(tether_constraints(ctx, infer))
        .simplify(ctx)
        .each_reachable_defn_with_cap(ctx).each do |rt, cap|
          # TODO: Support more element antecedent detection patterns.
          if rt.link == infer.prelude_type("Array") \
          && rt.args.size == 1
            results << {rt.args.first, cap}
          end
        end

      results
    end
  end

  class ArrayLiteralElementAntecedent < DynamicInfo
    getter array : ArrayLiteral

    def describe_kind; "array element" end

    def initialize(@pos, @array)
    end

    def tethers(querent : Info) : Array(Tether)
      return [] of Tether if querent == @array
      Tether.via(self, @array.tethers(querent))
    end

    def tether_upward_transform(ctx : Context, infer : ForReifiedFunc, meta_type : MetaType) : MetaType
      results = [] of MetaType

      meta_type.simplify(ctx).each_reachable_defn(ctx).each do |rt|
        # TODO: Support more element antecedent detection patterns.
        if rt.link == infer.prelude_type("Array") \
        && rt.args.size == 1
          results << rt.args.first.simplify(ctx)
        end
      end

      # TODO: support multiple antecedents gracefully?
      if results.size != 1
        return MetaType.unconstrained
      end

      results.first.not_nil!
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      antecedents = @array.possible_element_antecedents(ctx, infer)
      antecedents.empty? ? MetaType.unconstrained : MetaType.new_union(antecedents.map(&.first))
    end
  end

  class FromCall < DynamicInfo
    getter lhs : Info
    getter member : String
    getter args : AST::Group?
    getter yield_params : AST::Group?
    getter yield_block : AST::Group?
    getter ret_value_used : Bool
    getter resolvables : Array(Info)

    def initialize(@pos, @lhs, @member, @args, @yield_params, @yield_block, @ret_value_used)
      @resolvables = [] of Info
    end

    def describe_kind; "return value" end

    def tethers(querent : Info) : Array(Tether)
      return [] of Tether if querent == @lhs
      Tether.via(self, @lhs.tethers(querent))
    end

    def tether_upward_transform(ctx : Context, infer : ForReifiedFunc, meta_type : MetaType) : MetaType
      # TODO: is it possible to use the meta_type passed to us above,
      # at least in some cases, instead of eagerly resolving here?
      infer.resolve(ctx, self)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      meta_type = follow_call(ctx, infer)

      # TODO: auto-recovery of call result:

      # # If we have no downstreams, return now.
      # downstream = @downstreams[0][1] unless @downstreams.empty?
      # return meta_type unless downstream

      # # If recovering the call result would make no difference, return now.
      # meta_type_recovered = meta_type.alias.recovered
      # return meta_type if meta_type_recovered == meta_type.alias

      # # If the result value type matches downstream metatype, return it now.
      # downstream_mt = (
      #   downstream.as_downstream_constraint_meta_type(ctx, infer) ||
      #   infer.resolve_with_nil_on_reentrance(ctx, downstream)
      # )
      # return meta_type if downstream_mt.nil? || meta_type.subtype_of?(ctx, downstream_mt)

      # # If the type would work after recovering the result,
      # # see if it would be safe to do so by checking if all args are sendable.
      # if meta_type_recovered.subtype_of?(ctx, downstream_mt)
      #   if @yield_params.nil? && @yield_block.nil? \
      #   && infer.resolve(ctx, @lhs).is_sendable? \
      #   && (
      #     @args.nil? || @args.not_nil!.terms.all? { |arg|
      #       infer.resolve(ctx, infer.f_analysis[arg]).is_sendable?
      #     }
      #   )
      #     return meta_type_recovered
      #   else
      #     self.this_would_be_possible_if = {pos,
      #       "the receiver and all arguments were sendable"}
      #   end
      # end

      meta_type
    end

    def resolve_others!(ctx : Context, infer : ForReifiedFunc)
      infer.resolve(ctx, infer.f_analysis[@args.not_nil!]) if @args
      infer.resolve(ctx, infer.f_analysis[@yield_block.not_nil!]) if @yield_block
      infer.resolve(ctx, infer.f_analysis[@yield_params.not_nil!]) if @yield_params

      resolvables.each { |resolvable| infer.resolve(ctx, resolvable) }
    end

    def follow_call_get_call_defns(ctx : Context, infer : ForReifiedFunc) : Set({MetaType::Inner, ReifiedType?, Program::Function?})Set
      call = self
      receiver = infer.resolve_with_reentrance_prevention(ctx, @lhs)
      call_defns = receiver.find_callable_func_defns(ctx, infer, @member)

      # Raise an error if we don't have a callable function for every possibility.
      call_defns << {receiver.inner, nil, nil} if call_defns.empty?
      problems = [] of {Source::Pos, String}
      call_defns.each do |(call_mti, call_defn, call_func)|
        if call_defn.nil?
          problems << {@pos,
            "the type #{call_mti.inspect} has no referencable types in it"}
        elsif call_func.nil?
          call_defn_defn = call_defn.defn(ctx)

          problems << {call_defn_defn.ident.pos,
            "#{call_defn_defn.ident.value} has no '#{@member}' function"}

          found_similar = false
          if @member.ends_with?("!")
            call_defn_defn.find_func?(@member[0...-1]).try do |similar|
              found_similar = true
              problems << {similar.ident.pos,
                "maybe you meant to call '#{similar.ident.value}' (without '!')"}
            end
          else
            call_defn_defn.find_func?("#{@member}!").try do |similar|
              found_similar = true
              problems << {similar.ident.pos,
                "maybe you meant to call '#{similar.ident.value}' (with a '!')"}
            end
          end

          unless found_similar
            similar = call_defn_defn.find_similar_function(@member)
            problems << {similar.ident.pos,
              "maybe you meant to call the '#{similar.ident.value}' function"} \
                if similar
          end
        end
      end
      Error.at call,
        "The '#{@member}' function can't be called on #{receiver.show_type}",
          problems unless problems.empty?

      call_defns
    end

    def follow_call_check_receiver_cap(ctx : Context, infer : ForReifiedFunc, call_mt, call_func, problems)
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
        if @lhs.is_a?(Self)
          problems << {infer.func.cap.pos, "this would be possible if the " \
            "calling function were declared as `:fun #{required_cap}`"}
        end

        # We already failed subtyping for the receiver cap, but pretend
        # for now that we didn't for the sake of further checks.
        reify_cap = call_func_cap_mt
      end

      if autorecover_needed \
      && required_cap.value != "ref" && required_cap.value != "box"
        problems << {call_func.cap.pos,
          "the function's receiver capability is `#{required_cap}` " \
          "but only a `ref` or `box` receiver can be auto-recovered"}
      end

      {reify_cap, autorecover_needed}
    end

    def follow_call_check_args(ctx : Context, infer : ForReifiedFunc, call_func, other_infer, problems)
      call = self

      # Just check the number of arguments.
      # We will check the types in another Info type (TowardCallParam)
      arg_count = call.args.try(&.terms.size) || 0
      max = other_infer.params.size
      min = other_infer.params.count { |param| !AST::Extract.param(param)[2] }
      func_pos = call_func.ident.pos
      if arg_count > max
        max_text = "#{max} #{max == 1 ? "argument" : "arguments"}"
        params_pos = call_func.params.try(&.pos) || call_func.ident.pos
        problems << {call.pos, "the call site has too many arguments"}
        problems << {params_pos, "the function allows at most #{max_text}"}
        return
      elsif arg_count < min
        min_text = "#{min} #{min == 1 ? "argument" : "arguments"}"
        params_pos = call_func.params.try(&.pos) || call_func.ident.pos
        problems << {call.pos, "the call site has too few arguments"}
        problems << {params_pos, "the function requires at least #{min_text}"}
        return
      end
    end

    def follow_call_check_yield_block(other_infer, problems)
      yield_out_infos = other_infer.f_analysis.yield_out_infos

      if yield_out_infos.empty?
        if yield_block
          problems << {yield_block.not_nil!.pos, "it has a yield block " \
            "but the called function does not have any yields"}
        end
      elsif !yield_block
        problems << {yield_out_infos.first.first_viable_constraint_pos,
          "it has no yield block but the called function does yield"}
      end
    end

    def follow_call_check_autorecover_cap(ctx, infer, other_infer, inferred_ret)
      call = self

      # If autorecover of the receiver cap was needed to make this call work,
      # we now have to confirm that arguments and return value are all sendable.
      problems = [] of {Source::Pos, String}

      unless inferred_ret.is_sendable? || !call.ret_value_used
        problems << {other_infer.ret.pos,
          "the return type #{inferred_ret.show_type} isn't sendable " \
          "and the return value is used (the return type wouldn't matter " \
          "if the calling side entirely ignored the return value"}
      end

      # TODO: It should be safe to pass in a TRN if the receiver is TRN,
      # so is_sendable? isn't quite liberal enough to allow all valid cases.
      call.args.try(&.terms.each do |arg|
        inferred_arg = infer.resolve(ctx, infer.f_analysis[arg])
        unless inferred_arg.alias.is_sendable?
          problems << {arg.pos,
            "the argument (when aliased) has a type of " \
            "#{inferred_arg.alias.show_type}, which isn't sendable"}
        end
      end)

      Error.at call,
        "This function call won't work unless the receiver is ephemeral; " \
        "it must either be consumed or be allowed to be auto-recovered. "\
        "Auto-recovery didn't work for these reasons",
          problems unless problems.empty?
    end

    def follow_call_resolve_other_infers(ctx : Context, infer : ForReifiedFunc) : Set({ForReifiedFunc, Bool})
      other_infers = infer.analysis.call_infers_for[self]?
      return other_infers if other_infers

      other_infers = Set({ForReifiedFunc, Bool}).new

      call = self
      call_defns = follow_call_get_call_defns(ctx, infer)

      # For each receiver type definition that is possible, track down the infer
      # for the function that we're trying to call, evaluating the constraints
      # for each possibility such that all of them must hold true.
      problems = [] of {Source::Pos, String}
      call_defns.each do |(call_mti, call_defn, call_func)|
        call_mt = MetaType.new(call_mti)
        call_defn = call_defn.not_nil!
        call_func = call_func.not_nil!
        call_func_link = call_func.make_link(call_defn.link)

        # Keep track that we called this function.
        infer.analysis.called_funcs.add({call.pos, call_defn, call_func_link})

        reify_cap, autorecover_needed =
          follow_call_check_receiver_cap(ctx, infer, call_mt, call_func, problems)

        # Get the ForReifiedFunc instance for call_func, possibly creating and running it.
        # TODO: don't infer anything in the body of that func if type and params
        # were explicitly specified in the function signature.
        other_infer = ctx.infer.for_rf(ctx, call_defn, call_func_link, reify_cap).tap(&.run)

        follow_call_check_args(ctx, infer, call_func, other_infer, problems)
        follow_call_check_yield_block(other_infer, problems)

        other_infers.add({other_infer, autorecover_needed})
      end
      Error.at call,
        "This function call doesn't meet subtyping requirements",
          problems unless problems.empty?

      infer.analysis.call_infers_for[self] = other_infers
    end

    def follow_call(ctx : Context, infer : ForReifiedFunc)
      other_infers = follow_call_resolve_other_infers(ctx, infer)
      raise "this call didn't have any call defns:\n#{pos.show}" if other_infers.empty?

      rets = [] of MetaType
      other_infers.each do |other_infer, autorecover_needed|
        inferred_ret_info = other_infer.f_analysis[other_infer.ret]
        inferred_ret = other_infer.resolve_with_reentrance_prevention(ctx, inferred_ret_info)
        rets << inferred_ret

        if autorecover_needed
          follow_call_check_autorecover_cap(ctx, infer, other_infer, inferred_ret)
        end
      end

      # Constrain the return value as the union of all observed return types.
      ret = rets.size == 1 ? rets.first : MetaType.new_union(rets)

      ret.ephemeralize
    end
  end

  class FromCallYieldOut < DynamicInfo
    getter call : FromCall
    getter index : Int32

    def describe_kind; "value yielded to this block" end

    def initialize(@pos, @call, @index)
    end

    def tethers(querent : Info) : Array(Tether)
      # TODO: is it possible to tether downward to the below chain of @call
      [Tether.new(self)]
    end

    def tether_resolve(ctx : Context, infer : ForReifiedFunc)
      infer.resolve(ctx, self)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      # We must first resolve the FromCall itself to collect the other_infers.
      infer.resolve(ctx, @call)
      other_infers = infer.analysis.call_infers_for[@call]

      # TODO: Figure out how to support this multiple call defns case somehow.
      # It may be easier now that FromCall has been made more lazy?
      raise NotImplementedError.new("yield_block with multiple other_infers") \
        if other_infers.size > 1
      other_infer = other_infers.first.first

      raise "TODO: Nice error message for this" \
        if other_infer.f_analysis.yield_out_infos.size <= @index

      yield_param = call.yield_params.not_nil!.terms[@index]
      yield_out = other_infer.f_analysis.yield_out_infos[@index]

      @pos = yield_out.first_viable_constraint_pos

      other_infer.resolve(ctx, yield_out)
    end
  end

  class TowardCallYieldIn < DynamicInfo
    getter call : FromCall

    def describe_kind; "expected for the yield result" end

    def initialize(@pos, @call)
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      # We must first resolve the FromCall itself to collect the other_infers.
      infer.resolve(ctx, @call)
      other_infers = infer.analysis.call_infers_for[@call]

      # TODO: Figure out how to support this multiple call defns case somehow.
      # It may be easier now that FromCall has been made more lazy?
      raise NotImplementedError.new("yield_block with multiple other_infers") \
        if other_infers.size > 1
      other_infer = other_infers.first.first

      # Check that the type of the yield block result matches what's expected,
      # but don't bother if the type requirement of just None.
      yield_in_resolved = other_infer.resolve(ctx, other_infer.f_analysis.yield_in_info)
      none = MetaType.new(infer.reified_type(infer.prelude_type("None")))
      if yield_in_resolved != none
        yield_in_resolved
      else
        MetaType.unconstrained
      end
    end
  end

  class TowardCallParam < DynamicInfo
    getter call : FromCall
    getter index : Int32

    def describe_kind; "parameter for this argument" end

    def initialize(@pos, @call, @index)
    end

    def tethers(querent : Info) : Array(Tether)
      # TODO: is it possible to tether downward to the below chain of @call.lhs?
      [Tether.new(self)]
    end

    def tether_resolve(ctx : Context, infer : ForReifiedFunc)
      resolve!(ctx, infer) # TODO: should this be infer.resolve(ctx, self) instead?
    end

    def as_multiple_downstream_constraints(ctx : Context, infer : ForReifiedFunc) : Array({Source::Pos, MetaType})?
      other_infers = @call.follow_call_resolve_other_infers(ctx, infer)

      other_infers.map do |other_infer, _|
        param = other_infer.params[@index]
        param_info = other_infer.f_analysis[param]
        param_info = param_info.lhs if param_info.is_a?(FromAssign)
        param_info = param_info.as(Param)
        param_mt = other_infer.resolve(ctx, param_info)

        {param_info.first_viable_constraint_pos, param_mt}.as({Source::Pos, MetaType})
      end
    end

    def resolve!(ctx : Context, infer : ForReifiedFunc)
      other_infers = @call.follow_call_resolve_other_infers(ctx, infer)

      MetaType.new_intersection(
        other_infers.map do |other_infer, _|
          param = other_infer.params[@index]
          other_infer.resolve(ctx, other_infer.f_analysis[param]).as(MetaType)
        end
      )
    end
  end
end
