module Savi::Compiler::Infer
  struct Tether
    def initialize(@info : Info, @below : StructRef(Tether)? = nil)
    end

    def self.via(info : Info, list : Array(Tether)) : Array(Tether)
      list.map { |below| new(info, StructRef(Tether).new(below)) }
    end

    def self.chain(info : Info, querent : Info) : Array(Tether)
      if info == querent
        [] of Tether
      elsif info.tether_terminal?
        [new(info)]
      else
        via(info, info.tethers(querent))
      end
    end

    def root : Info
      below = @below
      below ? below.root : @info
    end

    def to_a : Array(Info)
      below = @below
      below ? below.to_a.tap(&.push(@info)) : [@info]
    end

    def constraint_span(ctx : Context, infer : Visitor) : Span
      below = @below
      if below
        @info.tether_upward_transform_span(ctx, infer, below.constraint_span(ctx, infer))
      else
        @info.tether_resolve_span(ctx, infer)
      end
    end

    def includes?(other_info) : Bool
      @info == other_info || @below.try(&.includes?(other_info)) || false
    end
  end

  abstract class Info
    property pos : Source::Pos = Source::Pos.none
    property! layer_index : Int32 # Corresponding to TypeContext::Analysis
    property override_describe_kind : String?

    def to_s
      "#<#{self.class.name.split("::").last} #{pos.inspect}>"
    end

    abstract def add_downstream(use_pos : Source::Pos, info : Info)

    def as_conduit? : Conduit?
      nil # if non-nil, a conduit will be used instead of a span.
    end
    def as_upstream_conduits : Array(Conduit)
      conduit = as_conduit?
      if conduit
        conduit.flatten
      else
        [Conduit.direct(self)]
      end
    end
    def resolve_span!(ctx : Context, infer : Visitor)
      raise NotImplementedError.new("resolve_span! for #{self.class}")
    end

    abstract def tethers(querent : Info) : Array(Tether)
    def tether_terminal?
      false
    end
    def tether_upward_transform_span(ctx : Context, infer : Visitor, span : Span) : Span
      raise NotImplementedError.new("tether_upward_transform_span for #{self.class}:\n#{pos.show}")
    end
    def tether_resolve_span(ctx : Context, infer : Visitor)
      raise NotImplementedError.new("tether_resolve_span for #{self.class}:\n#{pos.show}")
    end

    # Most Info types ignore hints, but a few override this method to see them,
    # or to pass them along to other nodes that may wish to see them.
    def add_peer_hint(peer : Info)
    end

    # In the rare case that an Info subclass needs to dynamically pretend to be
    # a different downstream constraint, it can override this method.
    # If you need to report multiple positions, also override the other method
    # below called as_multiple_downstream_constraints.
    # This will prevent upstream DynamicInfos from eagerly resolving you.
    def as_downstream_constraint_meta_type(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : MetaType?
      type_check.resolve(ctx, self)
    end

    # In the rare case that an Info subclass needs to dynamically pretend to be
    # multiple different downstream constraints, it can override this method.
    # This is only used to report positions in more detail, and it is expected
    # that the intersection of all MetaTypes here is the same as the resolve.
    def as_multiple_downstream_constraints(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : Array({Source::Pos, MetaType})?
      nil
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
    @downstreams = [] of Tuple(Source::Pos, Info)
    def add_downstream(use_pos : Source::Pos, info : Info)
      @downstreams << {use_pos, info}
      after_add_downstream(use_pos, info,)
    end
    def downstreams_empty?
      @downstreams.empty?
    end
    def downstream_use_pos
      @downstreams.first[0]
    end
    def downstreams_each; @downstreams.each; end

    # May be implemented by the child class as an optional hook.
    def after_add_downstream(use_pos : Source::Pos, info : Info)
    end

    def downstream_tethers(querent : Info) : Array(Tether)
      @downstreams.flat_map do |pos, info|
        Tether.chain(info, querent).as(Array(Tether))
      end
    end

    def tethers(querent : Info) : Array(Tether)
      downstream_tethers(querent)
    end

    def tether_constraint_spans(ctx : Context, infer : Visitor)
      tethers(self).map(&.constraint_span(ctx, infer).as(Span))
    end

    # When we need to take into consideration the downstreams' constraints
    # in order to infer our type from them, we can use this to collect all
    # those constraints into one intersection of them all.
    def total_downstream_constraint(ctx : Context, type_check : TypeCheck::ForReifiedFunc)
      MetaType.new_intersection(
        @downstreams.compact_map do |_, other_info|
          other_info.as_downstream_constraint_meta_type(ctx, type_check).as(MetaType?)
        end
      )
    end

    def list_downstream_constraints(ctx : Context, type_check : TypeCheck::ForReifiedFunc)
      list = Array({Source::Pos, MetaType}).new
      @downstreams.each do |_, info|
        multi = info.as_multiple_downstream_constraints(ctx, type_check)
        if multi
          list.concat(multi)
        else
          mt = type_check.resolve(ctx, info)
          list.push({info.pos, mt}) if mt
        end
      end
      list.to_h.to_a
    end

    def describe_downstream_constraints(ctx : Context, type_check : TypeCheck::ForReifiedFunc)
      list_downstream_constraints(ctx, type_check).map { |other_pos, mt|
        {other_pos, "it is required here to be a subtype of #{mt.show_type}"}
      }
    end

    # This property can be set to give a hint in the event of a typecheck error.
    property this_would_be_possible_if : Tuple(Source::Pos, String)?
  end

  abstract class NamedInfo < DynamicInfo
    @explicit : Info?
    @upstreams = [] of Tuple(Info, Source::Pos)

    def initialize(@pos, @layer_index)
    end

    def upstream_infos; @upstreams.map(&.first) end

    def adds_alias; 1 end

    def first_viable_constraint_pos : Source::Pos
      (downstream_use_pos unless downstreams_empty?)
      @upstreams[0]?.try(&.[1]) ||
      @pos
    end

    def explicit? : Bool
      !!@explicit
    end

    def explicit_is_type_expr_cap? : Bool
      explicit = @explicit
      return false unless explicit.is_a?(FixedTypeExpr)

      Infer.is_type_expr_cap?(explicit.node)
    end

    def set_explicit(explicit : Info)
      raise "already set_explicit" if @explicit
      raise "shouldn't have an upstream yet" unless @upstreams.empty?

      @explicit = explicit
      @pos = explicit.pos
    end

    def as_conduit? : Conduit?
      # If we have an explicit type that is not just a cap, we aren't a conduit.
      return nil if @explicit && !explicit_is_type_expr_cap?

      # Only do conduit for Local variables, not any other NamedInfo.
      # TODO: Can/should we remove this limitation somehow,
      # or at least move this method override to that subclass instead?
      return nil unless is_a?(Local)

      # If the first immediate upstream is another NamedInfo, conduit to it.
      return nil if @upstreams.empty?
      return nil unless (upstream = @upstreams.first.first).is_a?(NamedInfo)
      Conduit.direct(upstream)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      explicit = @explicit

      span =
      if explicit
        explicit_span = infer.resolve(ctx, explicit)

        if !explicit_span.any_mt?(&.cap_only?)
          # If we have an explicit type that is more than just a cap, return it.
          explicit_span
        elsif !@upstreams.empty?
          # If there are upstreams, use the explicit cap applied to the type of
          # each span entry of the upstreams, which becomes the canonical span.
          # TODO: use all upstreams if we can avoid infinite recursion
          upstream_span = infer.resolve(ctx, @upstreams.first.first)
          upstream_span.combine_mt(explicit_span) { |upstream_mt, cap_mt|
            upstream_mt.strip_cap.intersect(cap_mt)
          }
        else
          # If we have no upstreams and an explicit cap, return a span with
          # the empty trait called `Any` intersected with that cap.
          explicit_span.transform_mt do |explicit_mt|
            any = MetaType.new_nominal(infer.core_savi_reified_type(ctx, "Any"))
            any.intersect(explicit_mt)
          end
        end
      elsif !@upstreams.empty? && (upstream_span = resolve_upstream_span(ctx, infer))
        # If we only have upstreams to go on, return the first upstream span.
        # TODO: use all upstreams if we can avoid infinite recursion
        upstream_span
      elsif !downstreams_empty?
        # If we only have downstream tethers, just do our best with those.
        Span.reduce_combine_mts(
          tether_constraint_spans(ctx, infer)
        ) { |accum, mt| accum.intersect(mt) }
        .not_nil!
      else
        # If we get here, we've failed and don't have enough info to continue.
        Span.error self,
          "This #{described_kind} needs an explicit type; it could not be inferred"
      end

      if is_a?(FuncBody)
        span # do not stabilize the return type of a function body
      else
        span.transform_mt(&.stabilized)
      end
    end

    def tethers(querent : Info) : Array(Tether)
      results = [] of Tether
      results.concat(Tether.chain(@explicit.not_nil!, querent)) if @explicit
      @downstreams.each do |pos, info|
        results.concat(Tether.chain(info, querent))
      end
      results
    end

    def after_add_downstream(use_pos : Source::Pos, info : Info)
      return if @explicit && !explicit_is_type_expr_cap?

      @upstreams.each do |upstream, upstream_pos|
        upstream.add_downstream(use_pos, info)
      end
    end

    def tether_upward_transform_span(ctx : Context, infer : Visitor, span : Span) : Span
      # TODO: aliasing/ephemerality
      span
    end

    def assign(ctx : Context, upstream : Info, upstream_pos : Source::Pos)
      @upstreams << {upstream, upstream_pos}

      if @explicit && !explicit_is_type_expr_cap?
        upstream.add_downstream(upstream_pos, @explicit.not_nil!)
      else
        upstream.add_downstream(upstream_pos, self)
      end
    end

    # By default, a NamedInfo will only treat the first assignment as relevant
    # for inferring when there is no explicit, but some subclasses may override.
    def infer_from_all_upstreams? : Bool; false end
    private def resolve_upstream_span(ctx : Context, infer : Visitor) : Span?
      use_upstream_infos =
        infer_from_all_upstreams? ? upstream_infos : [upstream_infos.first]

      upstream_spans =
        use_upstream_infos.flat_map(&.as_upstream_conduits).compact_map do |upstream_conduit|
          next if upstream_conduit.directly_references?(self)
          upstream_conduit.resolve_span!(ctx, infer)
        end

      Span.reduce_combine_mts(upstream_spans) { |accum, mt| accum.unite(mt) }
    end
  end

  class ErrorInfo < Info
    getter error : Error

    def pos; error.pos; end

    def layer_index; 0; end

    def describe_kind; ""; end

    def initialize(*args)
      @error = Error.build(*args)
    end

    def add_downstream(use_pos : Source::Pos, info : Info)
      nil
    end

    def tethers(querent : Info) : Array(Tether)
      [] of Tether
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      Span.new(Span::ErrorPropagate.new(error))
    end
  end

  abstract class FixedInfo < DynamicInfo # TODO: rename or split DynamicInfo to make this line make more sense
    def tether_terminal?
      true
    end

    def tether_resolve_span(ctx : Context, infer : Visitor)
      infer.resolve(ctx, self)
    end
  end

  class FixedPrelude < FixedInfo
    getter name : String

    def describe_kind : String; "expression" end

    def initialize(@pos, @layer_index, @name)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.core_savi_type_span(ctx, @name)
    end
  end

  class FixedTypeExpr < FixedInfo
    getter node : AST::Node
    property stabilize : Bool

    def describe_kind : String; "type expression" end

    def initialize(@pos, @layer_index, @node)
      @stabilize = false
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.unwrap_lazy_parts_of_type_expr_span(ctx,
        infer.type_expr_span(ctx, @node)
      )
      .transform_mt { |mt| stabilize ? mt.stabilized : mt }
    end
  end

  class FixedEnumValue < FixedInfo
    getter node : AST::Node

    def describe_kind : String; "expression" end

    def initialize(@pos, @layer_index, @node)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.unwrap_lazy_parts_of_type_expr_span(ctx,
        infer.type_expr_span(ctx, @node)
      )
    end
  end

  class FixedSingleton < FixedInfo
    getter node : AST::Node
    getter type_param_ref : Refer::TypeParam?

    def describe_kind : String; "singleton value for this type" end

    def initialize(@pos, @layer_index, @node, @type_param_ref = nil)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      # If this node is further qualified, we don't want to bother resolving it,
      # and doing so would trigger errors during type argument validation,
      # because the type arguments haven't been applied yet; they will be
      # applied in a different FixedSingleton that wraps this one in range.
      # We don't have to resolve it because nothing will ever be its downstream.
      return Span.simple(MetaType.unconstrained) \
        if @node.is_a?(AST::Identifier) \
        && infer.classify.further_qualified?(@node)

      infer.unwrap_lazy_parts_of_type_expr_span(ctx,
        infer.type_expr_span(ctx, @node).transform_mt(&.override_cap(Infer::Cap::NON))
      )
    end
  end

  class Self < FixedInfo
    property stabilize : Bool

    def describe_kind : String; "receiver value" end

    def initialize(@pos, @layer_index)
      @stabilize = false
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.self_type_expr_span(ctx)
      .transform_mt { |mt| stabilize ? mt.stabilized : mt }
    end
  end

  class FromConstructor < FixedInfo
    def describe_kind : String; "constructed object" end

    def initialize(@pos, @layer_index, @cap : String)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.self_with_specified_cap(ctx, @cap)
    end
  end

  class AddressOf < DynamicInfo
    getter variable : Info

    def describe_kind : String; "address of this variable" end

    def initialize(@pos, @layer_index, @variable)
    end
  end

  class StackAddressOfVariable < DynamicInfo
    getter variable_type : Info

    def describe_kind : String; "variable address" end

    def initialize(@pos, @layer_index, @variable_type)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.core_savi_type_span(ctx, "CPointer")
        .combine_mt(infer.resolve(ctx, @variable_type)) { |target_mt, arg_mt|
          MetaType.new(ReifiedType.new(target_mt.single!.link, [arg_mt]))
        }
    end
  end

  class StaticAddressOfFunction < DynamicInfo
    getter receiver_type : Info
    getter function_name : String

    def describe_kind : String; "function address" end

    def initialize(@pos, @layer_index, @receiver_type, @function_name)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      # Take note of this captured function pointer.
      infer.analysis.captured_function_pointers.add(self)

      infer.core_savi_type_span(ctx, "CPointer", "None")
    end
  end

  class ReflectionOfType < DynamicInfo
    getter reflect_type : Info

    def describe_kind : String; "type reflection" end

    def initialize(@pos, @layer_index, @reflect_type)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      # Take note of this reflection.
      infer.analysis.reflections.add(self)

      infer.core_savi_type_span(ctx, "ReflectionOfType")
        .combine_mt(infer.resolve(ctx, @reflect_type)) { |target_mt, arg_mt|
          MetaType.new(ReifiedType.new(target_mt.single!.link, [arg_mt]))
        }
    end
  end

  class Literal < DynamicInfo
    getter peer_hints

    def describe_kind : String; "literal value" end

    def initialize(@pos, @layer_index, @possible : MetaType, @fallback : MetaType)
      @peer_hints = [] of Info
    end

    def add_peer_hint(peer : Info)
      @peer_hints << peer
    end

    def widest_mt
      @possible
    end

    def fallback_mt
      @fallback
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      simple_span = Span.simple(@possible)
      fallback_span = Span.simple(@fallback)

      # Look at downstream tether constraints to try to resolve the literal
      # to a more specific type than the simple "possible" type indicated by it.
      constrained_span =
        Span.reduce_combine_mts(
          tether_constraint_spans(ctx, infer)
        ) { |accum, mt| accum.intersect(mt) }.try { |constraint_span|
          constraint_span.combine_mt(simple_span) { |constraint_mt, mt|
            constrained_mt = mt.intersect(constraint_mt)
            constrained_mt.unsatisfiable? ? @possible : constrained_mt
          }
        } || simple_span

      peer_hints_span = Span.reduce_combine_mts(
        @peer_hints.map { |peer| infer.resolve(ctx, peer).as(Span) }
      ) { |accum, mt| accum.intersect(mt) }

      constrained_span
      .maybe_fallback_based_on_mt_simplify([
        # If we don't satisfy the constraints, go with our simply type
        # and let the type checker print a message about why it doesn't work.
        {:mt_unsatisfiable, simple_span},

        # If, after constraining, we are still not a single concrete type,
        # try to apply peer hints to the constrained type if any are available.
        {:mt_non_singular_concrete,
          if peer_hints_span
            constrained_span.combine_mt(peer_hints_span) { |constrained_mt, peers_mt|
              hinted_mt = constrained_mt.intersect(peers_mt)
              hinted_mt.unsatisfiable? ? @possible : hinted_mt
            }
            .maybe_fallback_based_on_mt_simplify([
              # If, with peer hints, we are still not a single concrete type,
              # there's nothing more to try, so we use the fallback type.
              {:mt_non_singular_concrete, fallback_span}
            ])
          else
            fallback_span
          end
        }
      ])
    end
  end

  class LocalRef < DynamicInfo
    getter info : DynamicInfo
    getter ref : Refer::Local

    def describe_kind : String; info.describe_kind end

    def initialize(@info, @layer_index, @ref)
    end

    def pos
      @info.pos
    end

    def add_downstream(use_pos : Source::Pos, info : Info)
      super(use_pos, info)
      @info.add_downstream(use_pos, info)
    end

    def tethers(querent : Info) : Array(Tether)
      @info.tethers(querent)
    end

    def add_peer_hint(peer : Info)
      @info.add_peer_hint(peer)
    end

    def as_conduit? : Conduit?
      Conduit.aliased(@info)
    end
  end

  class FuncBody < NamedInfo
    getter early_returns : Array(JumpReturn)
    def initialize(pos, layer_index, @early_returns)
      super(pos, layer_index)

      early_returns.each(&.term.try(&.add_downstream(@pos, self)))
    end
    def describe_kind : String; "function body" end

    def infer_from_all_upstreams? : Bool; true end
  end

  class Local < NamedInfo
    def describe_kind : String; "local variable" end
  end

  class Param < NamedInfo
    def describe_kind : String; "parameter" end
  end

  class YieldIn < NamedInfo
    def describe_kind : String; "yielded argument" end
  end

  class YieldOut < NamedInfo
    def describe_kind : String; "yielded result" end
  end

  class Field < DynamicInfo
    getter name : String

    def initialize(@pos, @layer_index, @name)
      @upstreams = [] of Info
    end

    def describe_kind : String; "field reference" end

    def assign(ctx : Context, upstream : Info, upstream_pos : Source::Pos)
      upstream.add_downstream(upstream_pos, self)
      @upstreams << upstream
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.self_type_expr_span(ctx).transform_mt_to_span do |call_mt|
        call_defn = call_mt.single!
        call_func = call_defn.defn(ctx).functions.find do |f|
          f.ident.value == @name && f.has_tag?(:field)
        end.not_nil!

        call_link = call_func.make_link(call_defn.link)
        infer.depends_on_call_ret_span(ctx, call_defn, call_func, call_link,
            call_mt.cap_only_inner.value.as(Cap))
      end
    rescue error : Error
      Span.new(Span::ErrorPropagate.new(error))
    end

    def tether_terminal?
      true
    end

    def tether_resolve_span(ctx : Context, infer : Visitor)
      infer.resolve(ctx, self)
    end
  end

  class FieldRead < DynamicInfo
    getter :field

    def initialize(@field : Field, @origin : Self)
      @layer_index = @field.layer_index
    end

    def describe_kind : String; "field read" end

    def pos
      @field.pos
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      origin_span = infer.resolve(ctx, @origin)
      field_span = infer.resolve(ctx, @field)
      origin_span.combine_mt(field_span) { |o, f| f.viewed_from(o).aliased }
    end
  end

  class FieldExtract < DynamicInfo
    def initialize(@field : Field, @origin : Self)
      @layer_index = @field.layer_index
    end

    def describe_kind : String; "field extraction" end

    def pos
      @field.pos
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      origin_span = infer.resolve(ctx, @origin)
      field_span = infer.resolve(ctx, @field)
      origin_span.combine_mt(field_span) { |o, f| f.viewed_from(o) }
    end
  end

  abstract class JumpInfo < Info
    getter term : Info
    def initialize(@pos, @layer_index, @term)
    end

    def describe_kind : String; "control flow jump" end

    abstract def error_jump_name

    def add_downstream(use_pos : Source::Pos, info : Info)
      Error.at use_pos,
        "\"#{error_jump_name}\" expression never returns any value"
    end

    def tethers(querent : Info) : Array(Tether)
      term.tethers(querent)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      # A jump expression has no result value, so the resolved type is always
      # unconstrained - the term's type goes to the jump's catching entity.
      Span.simple(MetaType.unconstrained)
    end
  end

  class JumpError < JumpInfo
    def error_jump_name; "error!" end
  end

  class JumpReturn < JumpError
    def error_jump_name; "return" end
  end

  class JumpBreak < JumpError
    def error_jump_name; "break" end
  end

  class JumpNext < JumpError
    def error_jump_name; "next" end
  end

  class Sequence < Info
    getter terms : Array(Info)
    getter final_term : Info

    def describe_kind : String; "sequence" end

    def initialize(pos, @layer_index, @terms)
      @final_term = @terms.empty? ? FixedPrelude.new(pos, @layer_index, "None") : @terms.last
      @pos = @final_term.pos
    end

    def add_downstream(use_pos : Source::Pos, info : Info)
      final_term.add_downstream(use_pos, info)
    end

    def tethers(querent : Info) : Array(Tether)
      final_term.tethers(querent)
    end

    def add_peer_hint(peer : Info)
      final_term.add_peer_hint(peer)
    end

    def as_conduit? : Conduit?
      Conduit.direct(@final_term)
    end
  end

  # TODO: add some kind of logic for analyzing exhausted choices,
  # as well as necessary/sufficient conditions for each branch to be in play
  # letting us better specialize the codegen later by eliminating impossible
  # branches in particular reifications of this type or function.
  abstract class Phi < DynamicInfo
    getter fixed_bool : Info
    getter branches : Array({Info?, Info, Bool})

    def describe_kind : String; "choice block" end

    def initialize(@pos, @layer_index, @branches, @fixed_bool)
      prior_bodies = [] of Info
      @branches.each do |cond, body, body_jumps_away|
        next if body_jumps_away
        body.add_downstream(@pos, self)
        prior_bodies.each { |prior_body| body.add_peer_hint(prior_body) }
        prior_bodies << body
      end

      # Each condition must evaluate to a type of Bool.
      @branches.each do |cond, body, body_jumps_away|
        cond.add_downstream(pos, @fixed_bool) if cond
      end
    end

    def as_conduit? : Conduit?
      # TODO: Keep in separate span points instead of union if any of the conds
      # can be statically determinable, leaving room for specialization.
      Conduit.union(
        @branches.compact_map do |cond, body, body_jumps_away|
          body unless body_jumps_away
        end
      )
    end

    def tether_upward_transform_span(ctx : Context, infer : Visitor, span : Span) : Span
      # TODO: account for unreachable branches? maybe? maybe not?
      span
    end

    def as_downstream_constraint_meta_type(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : MetaType
      total_downstream_constraint(ctx, type_check)
    end

    def as_multiple_downstream_constraints(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : Array({Source::Pos, MetaType})?
      @downstreams.flat_map do |pos, info|
        multi = info.as_multiple_downstream_constraints(ctx, type_check)
        next multi if multi

        mt = info.as_downstream_constraint_meta_type(ctx, type_check)
        next {info.pos, mt} if mt

        [] of {Source::Pos, MetaType}
      end
    end
  end

  class Loop < Phi
    getter early_breaks : Array(JumpBreak)
    getter early_nexts : Array(JumpNext)

    def initialize(pos, layer_index, branches, fixed_bool, @early_breaks, @early_nexts)
      super(pos, layer_index, branches, fixed_bool)

      early_breaks.each(&.term.add_downstream(@pos, self))
      early_nexts.each(&.term.add_downstream(@pos, self))
    end
  end

  class Choice < Phi
  end

  class TypeParamCondition < FixedInfo
    getter refine : Refer::TypeParam
    getter lhs : Info
    getter refine_type : Info
    getter positive_check : Bool

    def describe_kind : String; "type parameter condition" end

    def initialize(@pos, @layer_index, @refine, @lhs, @refine_type, @positive_check)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.core_savi_type_span(ctx, "Bool")
    end
  end

  class TypeCondition < FixedInfo
    getter lhs : Info
    getter rhs : Info
    getter positive_check : Bool

    def describe_kind : String; "type condition" end

    def initialize(@pos, @layer_index, @lhs, @rhs, @positive_check)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.core_savi_type_span(ctx, "Bool")
    end
  end

  class TypeConditionForLocal < FixedInfo
    getter refine : AST::Node
    getter refine_type : Info
    getter positive_check : Bool

    def describe_kind : String; "type condition" end

    def initialize(@pos, @layer_index, @refine, @refine_type, @positive_check)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.core_savi_type_span(ctx, "Bool")
    end
  end

  class TypeConditionStatic < FixedInfo
    getter lhs : Info
    getter rhs : Info
    getter positive_check : Bool

    def describe_kind : String; "static type condition" end

    def initialize(@pos, @layer_index, @lhs, @rhs, @positive_check)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.core_savi_type_span(ctx, "Bool")
    end
  end

  class Refinement < DynamicInfo
    getter refine : Info
    getter refine_type : Info
    getter positive_check : Bool

    def describe_kind : String; "type refinement" end

    def initialize(@pos, @layer_index, @refine, @refine_type, @positive_check)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      infer.resolve(ctx, @refine)
      .combine_mt(infer.resolve(ctx, @refine_type)) { |lhs_mt, rhs_mt|
        rhs_mt = rhs_mt.strip_cap.negate if !@positive_check
        lhs_mt.intersect(rhs_mt)
      }
    end
  end

  class Consume < Info
    getter local : Info

    def describe_kind : String; "consumed reference" end

    def initialize(@pos, @layer_index, @local)
    end

    def as_conduit? : Conduit?
      local = local()
      local = local.info if local.is_a?(LocalRef)
      Conduit.consumed(local)
    end

    def add_downstream(use_pos : Source::Pos, info : Info)
      local = local()
      local = local.info if local.is_a?(LocalRef)
      local.add_downstream(use_pos, info)
    end

    def tethers(querent : Info) : Array(Tether)
      Tether.chain(@local, querent)
    end

    def add_peer_hint(peer : Info)
      @local.add_peer_hint(peer)
    end
  end

  class RecoverUnsafe < Info
    getter body : Info

    def describe_kind : String; "recover block" end

    def initialize(@pos, @layer_index, @body)
    end

    def add_downstream(use_pos : Source::Pos, info : Info)
      # TODO: Make recover safe.
      # @body.add_downstream(use_pos, info)
    end

    def tethers(querent : Info) : Array(Tether)
      Tether.chain(@body, querent)
    end

    def tether_upward_transform_span(ctx : Context, infer : Visitor, span : Span) : Span
      span.transform_mt(&.strip_cap)
    end

    def add_peer_hint(peer : Info)
      @body.add_peer_hint(peer)
    end
  end

  class FromAssign < Info
    getter lhs : NamedInfo
    getter rhs : Info

    def describe_kind : String; "assign result" end

    def initialize(@pos, @layer_index, @lhs, @rhs)
    end

    def add_downstream(use_pos : Source::Pos, info : Info)
      @lhs.add_downstream(use_pos, info)
    end

    def tethers(querent : Info) : Array(Tether)
      Tether.chain(@lhs, querent)
    end

    def add_peer_hint(peer : Info)
      @lhs.add_peer_hint(peer)
    end

    def as_conduit? : Conduit?
      Conduit.aliased(@lhs)
    end
  end

  class FromYield < Info
    getter yield_in : Info
    getter terms : Array(Info)

    def describe_kind : String; "value returned by the yield block" end

    def initialize(@pos, @layer_index, @yield_in, @terms)
    end

    def add_downstream(use_pos : Source::Pos, info : Info)
      @yield_in.add_downstream(use_pos, info)
    end

    def tethers(querent : Info) : Array(Tether)
      Tether.chain(@yield_in, querent)
    end

    def add_peer_hint(peer : Info)
      @yield_in.add_peer_hint(peer)
    end

    def as_conduit? : Conduit?
      Conduit.direct(@yield_in)
    end
  end

  class ArrayLiteral < DynamicInfo
    getter terms : Array(Info)

    def describe_kind : String; "array literal" end

    def initialize(@pos, @layer_index, @terms)
    end

    def after_add_downstream(use_pos : Source::Pos, info : Info)
      # Only do this after the first downstream is added.
      return unless @downstreams.size == 1

      elem_downstream = ArrayLiteralElementAntecedent.new(@downstreams.first[1].pos, @layer_index, self)
      @terms.each do |term|
        term.add_downstream(downstream_use_pos, elem_downstream)
      end
    end

    def tether_upward_transform_span(ctx : Context, infer : Visitor, span : Span) : Span
      span
    end

    def possible_antecedents_span(ctx, infer) : Span?
      array_info = self
      tether_spans = tether_constraint_spans(ctx, infer)

      return nil if tether_spans.empty?

      ante_span =
        Span
        .reduce_combine_mts(tether_spans) { |accum, mt| accum.intersect(mt) }
        .not_nil!
        .transform_mt { |mt|
          ante_mts = mt.map_each_union_member { |union_member_mt|
            rt = union_member_mt.single_rt?
            next unless rt

            if rt.link.name == "Array" && rt.args.size == 1
              MetaType.new_nominal(rt).intersect(union_member_mt.cap_only)
            end
          }.compact
          ante_mts.empty? ? MetaType.unconstrained : MetaType.new_union(ante_mts)
        }

      ante_span unless ante_span.any_mt?(&.unconstrained?)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      # By default, an array literal has a cap of `ref`.
      # TODO: span should allow ref, val, or iso cap possibilities.
      array_cap = MetaType::Capability::REF

      ante_span = possible_antecedents_span(ctx, infer)

      elem_spans = terms.map { |term| infer.resolve(ctx, term).as(Span) }
      elem_span = Span
        .reduce_combine_mts(elem_spans) { |accum, mt| accum.unite(mt) }
        .try(&.transform_mt(&.stabilized))

      if ante_span
        if elem_span
          ante_span.combine_mt_to_span(elem_span) { |ante_mt, elem_mt|
            # We know/assert that the antecedent MetaType is in the form of
            # a cap intersected with an Array ReifiedType, so we know that
            # we can get the element MetaType from the ReifiedType's type args.
            ante_elem_mt = ante_mt.single!.args[0]
            fallback_rt = infer.core_savi_reified_type(ctx, "Array", [elem_mt])
            fallback_mt = MetaType.new(fallback_rt).intersect(MetaType.cap("ref"))

            # We may need to unwrap lazy elements from this inner layer.
            ante_elem_mt = infer
              .unwrap_lazy_parts_of_type_expr_span(ctx, Span.simple(ante_elem_mt))
              .inner.as(Span::Terminal).meta_type

            # For every pair of element MetaType and antecedent MetaType,
            # Treat the antecedent MetaType as the default, but
            # fall back to using the element MetaType if the intersection
            # of those two turns out to be unsatisfiable.
            Span.simple_with_fallback(ante_mt,
              ante_elem_mt.intersect(elem_mt), [
                {:mt_unsatisfiable, Span.simple(fallback_mt)}
              ]
            )
          }
        else
          ante_span
        end
      else
        if elem_span
          array_span = elem_span.transform_mt { |elem_mt|
            rt = infer.core_savi_reified_type(ctx, "Array", [elem_mt])
            MetaType.new(rt, Cap::REF)
          }
        else
          Span.error(pos, "The type of this empty array literal " \
            "could not be inferred (it needs an explicit type)")
        end
      end

      # Take note of the function calls implied (used later for reachability).
      .tap { |array_span|
        infer.analysis.called_func_spans[self] = {
          array_span.transform_mt(&.override_cap(Cap::REF)), # always use ref
          ["new", "<<"]
        }
      }
    end
  end

  class ArrayLiteralElementAntecedent < DynamicInfo
    getter array : ArrayLiteral

    def describe_kind : String; "array element" end

    def initialize(@pos, @layer_index, @array)
    end

    def as_conduit? : Conduit?
      Conduit.array_literal_element_antecedent(@array)
    end

    def tethers(querent : Info) : Array(Tether)
      Tether.chain(@array, querent)
    end

    def tether_upward_transform_span(ctx : Context, infer : Visitor, span : Span) : Span
      infer.unwrap_lazy_parts_of_type_expr_span(ctx,
        span.transform_mt do |meta_type|
          results = [] of MetaType

          meta_type.map_each_union_member do |union_member_mt|
            rt = union_member_mt.single_rt?
            next unless rt

            # TODO: Support more element antecedent detection patterns.
            if rt.link.name == "Array" \
            && rt.args.size == 1
              results << rt.args.first
            end
          end

          # TODO: support multiple antecedents gracefully?
          if results.size != 1
            next MetaType.unconstrained
          end

          results.first.not_nil!
        end
      )
    end
  end

  class FromCall < DynamicInfo
    getter lhs : Info
    getter member : String
    getter args : AST::Group?
    getter yield_params : AST::Group?
    getter yield_block : AST::Group?
    getter ret_value_used : Bool

    getter yield_block_breaks = [] of JumpBreak

    def initialize(@pos, @layer_index, @lhs, @member, @args, @yield_params, @yield_block, @ret_value_used)
    end

    protected def observe_break(jump : JumpBreak)
      @yield_block_breaks << jump
      jump.term.add_downstream(@pos, self)
    end

    def describe_kind : String; "return value" end

    def tethers(querent : Info) : Array(Tether)
      Tether.chain(@lhs, querent)
    end

    def tether_upward_transform_span(ctx : Context, infer : Visitor, span : Span) : Span
      # TODO: is it possible to use the meta_type passed to us above,
      # at least in some cases, instead of eagerly resolving here?
      infer.resolve(ctx, self)
    end

    def resolve_receiver_span(ctx : Context, infer : Visitor) : Span
      infer.analysis.called_func_spans[self]?.try(&.first) || begin
        call_receiver_span = infer.resolve(ctx, @lhs)
          .transform_mt_to_span(&.gather_call_receiver_span(ctx, @pos, infer, @member))

        # Save the call defn span to the analysis (used later for reachability).
        infer.analysis.called_func_spans[self] = {call_receiver_span, @member}

        call_receiver_span
      end
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      lhs_span = infer.resolve(ctx, @lhs)
      receiver_span = resolve_receiver_span(ctx, infer)

      receiver_span.combine_mt_to_span(lhs_span) { |call_receiver_mt, lhs_mt|
        union_member_spans = call_receiver_mt.map_each_union_member { |union_member_mt|
          intersection_term_spans = union_member_mt.map_each_intersection_term_and_or_cap { |term_mt|
            call_mt = union_member_mt
            call_defn = term_mt.single!
            call_func = call_defn.defn(ctx).find_func!(@member)
            call_link = call_func.make_link(call_defn.link)

            # If this is a constructor, we know what the result type will be
            # without needing to actually depend on the other analysis' span.
            if call_func.has_tag?(:constructor)
              new_mt = call_mt
                .intersect(lhs_mt)
                .strip_cap
                .intersect(MetaType.cap(call_func.cap.value))

              next Span.simple(new_mt)
            end

            infer
              .depends_on_call_ret_span(ctx, call_defn, call_func, call_link,
                call_mt.cap_only_inner.value.as(Cap))
          }
          Span.reduce_combine_mts(intersection_term_spans) { |accum, mt| accum.intersect(mt) }.not_nil!
        }
        Span.reduce_combine_mts(union_member_spans) { |accum, mt| accum.unite(mt) }.not_nil!
      }
    end
  end

  class FromCallYieldOut < DynamicInfo
    getter call : FromCall
    getter index : Int32

    def describe_kind : String; "value yielded to this block" end

    def initialize(@pos, @layer_index, @call, @index)
    end

    def tether_terminal?
      true
    end

    def tether_resolve_span(ctx : Context, infer : Visitor)
      infer.resolve(ctx, self)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      @call.resolve_receiver_span(ctx, infer).transform_mt_to_span { |call_receiver_mt|
        union_member_spans = call_receiver_mt.map_each_union_member { |union_member_mt|
          intersection_term_spans = union_member_mt.map_each_intersection_term_and_or_cap { |term_mt|
            call_defn = term_mt.single!
            call_func = call_defn.defn(ctx).find_func!(@call.member)
            call_link = call_func.make_link(call_defn.link)

            raw_ret_span = infer
              .depends_on_call_yield_out_span(ctx, call_defn, call_func, call_link,
                term_mt.cap_only_inner.value.as(Cap), @index)

            unless raw_ret_span
              call_name = "#{call_defn.defn(ctx).ident.value}.#{@call.member}"
              next Span.error(pos,
                "This yield block parameter will never be received", [
                  {call_func.ident.pos, "'#{call_name}' does not yield it"}
                ]
              )
            end

            raw_ret_span.not_nil!
          }
          Span.reduce_combine_mts(intersection_term_spans) { |accum, mt| accum.intersect(mt) }.not_nil!
        }
        Span.reduce_combine_mts(union_member_spans) { |accum, mt| accum.unite(mt) }.not_nil!
      }
    end
  end

  class TowardCallYieldIn < DynamicInfo
    getter call : FromCall

    getter yield_block_nexts = [] of JumpNext

    def describe_kind : String; "expected for the yield result" end

    def initialize(@pos, @layer_index, @call)
    end

    protected def observe_next(jump : JumpNext)
      @yield_block_nexts << jump
      jump.term.add_downstream(@pos, self)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      none = MetaType.new(infer.core_savi_reified_type(ctx, "None"))

      @call.resolve_receiver_span(ctx, infer).transform_mt_to_span { |call_receiver_mt|
        union_member_spans = call_receiver_mt.map_each_union_member { |union_member_mt|
          intersection_term_spans = union_member_mt.map_each_intersection_term_and_or_cap { |term_mt|
            call_defn = term_mt.single!
            call_func = call_defn.defn(ctx).find_func!(@call.member)
            call_link = call_func.make_link(call_defn.link)

            raw_ret_span = infer
              .depends_on_call_yield_in_span(ctx, call_defn, call_func, call_link,
                term_mt.cap_only_inner.value.as(Cap))

            next Span.simple(MetaType.unconstrained) unless raw_ret_span

            raw_ret_span.not_nil!
          }
          Span.reduce_combine_mts(intersection_term_spans) { |accum, mt| accum.intersect(mt) }.not_nil!
        }
        Span.reduce_combine_mts(union_member_spans) { |accum, mt| accum.intersect(mt) }.not_nil!
      }.transform_mt { |mt|
        # If the type requirement is None, treat it as unconstrained,
        # so that the caller need not specify an explicit None.
        # TODO: consider adding a special case Void type like Swift has?
        mt == none ? MetaType.unconstrained : mt
      }
    end
  end

  class TowardCallParam < DynamicInfo
    getter call : FromCall
    getter index : Int32

    def describe_kind : String; "parameter for this argument" end

    def initialize(@pos, @layer_index, @call, @index)
    end

    def tether_terminal?
      true
    end

    def tether_resolve_span(ctx : Context, infer : Visitor)
      resolve_span!(ctx, infer) # TODO: should this be infer.resolve(ctx, self) instead?
    end

    def as_multiple_downstream_constraints(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : Array({Source::Pos, MetaType})?
      rf = type_check.reified
      results = [] of {Source::Pos, MetaType}

      ctx.infer[rf.link].each_called_func_within(ctx, rf, for_info: @call) { |other_info, other_rf|
        next unless other_info == call

        param_mt = other_rf.meta_type_of_param(ctx, @index)
        next unless param_mt

        param = other_rf.link.resolve(ctx).params.not_nil!.terms.[@index]
        pre_infer = ctx.pre_infer[other_rf.link]
        param_info = pre_infer[param]
        param_info = param_info.lhs if param_info.is_a?(FromAssign)
        param_info = param_info.as(Param)
        results << {param_info.first_viable_constraint_pos, param_mt}
      }

      results
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      @call.resolve_receiver_span(ctx, infer).transform_mt_to_span { |call_receiver_mt|
        union_member_spans = call_receiver_mt.map_each_union_member { |union_member_mt|
          intersection_term_spans = union_member_mt.map_each_intersection_term_and_or_cap { |term_mt|
            call_defn = term_mt.single!
            call_func = call_defn.defn(ctx).find_func!(@call.member)
            call_link = call_func.make_link(call_defn.link)

            param_span = infer
              .depends_on_call_param_span(ctx, call_defn, call_func, call_link,
                term_mt.cap_only_inner.value.as(Cap), @index)

            next Span.simple(MetaType.unconstrained) unless param_span

            param_span
          }
          Span.reduce_combine_mts(intersection_term_spans) { |accum, mt| accum.intersect(mt) }.not_nil!
        }
        Span.reduce_combine_mts(union_member_spans) { |accum, mt| accum.intersect(mt) }.not_nil!
      }
    end
  end
end
