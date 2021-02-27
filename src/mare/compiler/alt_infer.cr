require "./pass/analyze"

##
# TODO: Document
#
# This pass is an experimental refactoring of the Infer pass, tracking
# the space of possibilities for a node's type as a Span, so that the Span
# can be resolved quickly later for any given reification.
# The expectation is that this approach will reduce compile times
# and maybe also provide more powerful inference capabilities.
#
# Currently this pass is not used for compilation, unless you use the
# --pass=alt_infer flag when running the `mare` binary.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the per-function level.
# This pass produces output state at the per-function level.
#
module Mare::Compiler::AltInfer
  alias Info = Infer::Info
  alias MetaType = Infer::MetaType
  alias ReifiedType = Infer::ReifiedType

  struct Span
    alias Key = Info | Symbol

    getter inner : Inner
    def initialize(@inner)
    end

    def pretty_print(format : PrettyPrint)
      format.surround("Span(", ")", left_break: nil, right_break: nil) do
        inner.pretty_print(format)
      end
    end

    def self.simple(mt : MetaType); new(Terminal.new(mt)); end

    def self.decision(key : Key, span_map : Hash(MetaType, Span))
      map = span_map.transform_values(&.inner)

      raise NotImplementedError.new("new decision key conflict") \
        if map.values.any?(&.has_key?(key))

      new(Decision.build(key, map))
    end

    def self.simple_with_fallback(
      default_mt : MetaType,
      evaluate_mt : MetaType,
      options : Array({Symbol, Span}),
    )
      new(Fallback.build(
        Terminal.new(default_mt),
        evaluate_mt,
        options.map { |(cond, span)| {cond, span.inner} }
      ))
    end

    def self.error(*args); new(ErrorPropagate.new(Error.build(*args))); end

    def self.self_with_reify_cap(ctx : Context, infer : Visitor)
      rt_args = infer
        .type_params_for(ctx, infer.link.type)
        .map { |type_param| MetaType.new_type_param(type_param) }

      rt = ReifiedType.new(infer.link.type, rt_args)
      f = infer.func
      f_cap_value = f.cap.value
      f_cap_value = "ref" if f.has_tag?(:constructor)
      f_cap_value = "read" if f_cap_value == "box" # TODO: figure out if we can remove this Pony-originating semantic hack
      Span.decision(
        :f_cap,
        MetaType::Capability.new_maybe_generic(f_cap_value).each_cap.map do |cap|
          cap_mt = MetaType.new(cap)
          {cap_mt, Span.simple(MetaType.new(rt).override_cap(cap_mt))}
        end.to_h
      )
    end

    def self.self_ephemeral_with_cap(ctx : Context, infer : Visitor, cap : String)
      rt_args = infer
        .type_params_for(ctx, infer.link.type)
        .map { |type_param| MetaType.new_type_param(type_param) }

      rt = ReifiedType.new(infer.link.type, rt_args)
      mt = MetaType.new(rt, cap).ephemeralize
      simple(mt)
    end

    def any_error?
      inner.any_error?
    end

    def total_error
      inner.total_error
    end

    def has_key?(key : Key) : Bool
      inner.has_key?(key)
    end

    # TODO: remove this function?
    def all_terminal_meta_types : Array(MetaType)
      inner.all_terminal_meta_types
    end

    def any_mt?(&block : MetaType -> Bool) : Bool
      inner.any_mt?(&block)
    end

    def transform_mt(&block : MetaType -> MetaType) : Span
      Span.new(inner.transform_mt(&block))
    end

    def transform_mt_using(key : Key, &block : (MetaType, MetaType?) -> MetaType) : Span
      Span.new(inner.transform_mt_using(key, nil, &block))
    end

    def decided_by(key : Key, &block : MetaType -> Enumerable({MetaType, Span})) : Span
      orig_keys = inner.gather_all_keys
      Span.new(inner.decided_by(key, orig_keys, &block))
    end

    def combine_mt_to_span(other : Span, &block : (MetaType, MetaType) -> Span) : Span
      Span.new(inner.combine_mt_to_span(other.inner, nil, &block))
    end

    def combine_mt(other : Span, &block : (MetaType, MetaType) -> MetaType) : Span
      mt_block = ->(a : MetaType, b : MetaType) {
        Span.simple(block.call(a, b))
      }
      Span.new(inner.combine_mt_to_span(other.inner, nil, &mt_block))
    end

    def combine_mts(spans : Array(Span), &block : (MetaType, Array(MetaType)) -> MetaType) : Span
      others = spans.map(&.inner)
      if inner.is_a?(Terminal) && others.all?(&.is_a?(Terminal))
        # If all are terminals, we can easily combine them with one block call.
        Span.new(Terminal.new(block.call(
          inner.as(Terminal).meta_type,
          others.map(&.as(Terminal).meta_type)
        )))
      elsif others.all?(&.==(inner))
        # If all spans are equivalent we can take a shortcut: using transform_mt
        # on just one of the spans, then presenting that to the block as if we
        # had gotten that value from all of the presented spans.
        transform_block = ->(mt : MetaType) { block.call(mt, spans.map { mt }) }
        Span.new(inner.transform_mt(&transform_block))
      else
        raise NotImplementedError.new("combine_mts")
      end
    end

    def self.combine_mts(spans : Array(Span), &block : Array(MetaType) -> MetaType) : Span?
      case spans.size
      when 0; nil
      when 1; spans.first
      when 2
        spans.first.combine_mt(spans.last) { |mt, other_mt|
          block.call([mt, other_mt])
        }
      else
        spans.first.combine_mts(spans[1..-1]) do |mt, other_mts|
          block.call([mt] + other_mts)
        end
      end
    end

    def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Span?
      inner.deciding_f_cap(f_cap_mt, is_constructor)
      .try { |new_inner| Span.new(new_inner) }
    end

    def maybe_fallback_based_on_mt_simplify(options : Array({Symbol, Span}))
      Span.new(inner.maybe_fallback_based_on_mt_simplify(
        options.map { |(cond, span)| {cond, span.inner} }
      ))
    end

    def final_mt_simplify(ctx : Context) : Span
      Span.new(inner.final_mt_simplify(ctx))
    end

    abstract struct Inner
      abstract def any_error? : Bool
      abstract def total_error : Error?
      abstract def has_key?(key : Key) : Bool
      abstract def gather_all_keys(set = Set(Key).new) : Set(Key)
      abstract def all_terminal_meta_types : Array(MetaType)
      abstract def any_mt?(&block : MetaType -> Bool) : Bool
      abstract def transform_mt(&block : MetaType -> MetaType) : Inner
      abstract def transform_mt_using(key : Key, maybe_value : MetaType?, &block : (MetaType, MetaType?) -> MetaType) : Inner
      abstract def decided_by(key : Key, orig_keys : Set(Key), &block : MetaType -> Enumerable({MetaType, Span})) : Inner
      abstract def combine_mt_to_span(other : Inner, maybe_other_terminal : Terminal?, &block : (MetaType, MetaType) -> Span) : Inner
      abstract def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Inner?
      abstract def maybe_fallback_based_on_mt_simplify(options : Array({Symbol, Inner})) : Inner
      abstract def final_mt_simplify(ctx : Context) : Inner
    end

    struct Terminal < Inner
      getter meta_type : MetaType
      def initialize(@meta_type)
      end

      def pretty_print(format : PrettyPrint)
        meta_type.inner.pretty_print(format)
      end

      def any_error? : Bool
        false
      end

      def total_error : Error?
        nil
      end

      def has_key?(key : Key) : Bool
        false
      end

      def gather_all_keys(set = Set(Key).new) : Set(Key)
        set
      end

      def all_terminal_meta_types : Array(MetaType)
        [@meta_type]
      end

      def any_mt?(&block : MetaType -> Bool) : Bool
        block.call(meta_type)
      end

      def transform_mt(&block : MetaType -> MetaType) : Inner
        Terminal.new(block.call(meta_type))
      end

      def transform_mt_using(key : Key, maybe_value : MetaType?, &block : (MetaType, MetaType?) -> MetaType) : Inner
        Terminal.new(block.call(meta_type, maybe_value))
      end

      def decided_by(key : Key, orig_keys : Set(Key), &block : MetaType -> Enumerable({MetaType, Span})) : Inner
        map = block.call(meta_type).to_h.transform_values(&.inner)

        new_keys = Set(Key).new
        map.each_value { |inner| inner.gather_all_keys(new_keys) }
        raise NotImplementedError.new("decision key conflict") \
          if new_keys.any? { |new_key| orig_keys.includes?(new_key) }

        Decision.build(key, map)
      end

      def combine_mt_to_span(other : Inner, maybe_other_terminal : Terminal?, &block : (MetaType, MetaType) -> Span) : Inner
        if maybe_other_terminal
          block.call(self.meta_type, maybe_other_terminal.meta_type).inner
        else
          swap_block = -> (b : MetaType, a : MetaType) { block.call(a, b) }
          other.combine_mt_to_span(self, self, &swap_block)
        end
      end

      def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Inner?
        self # a terminal node ignores f_cap_mt
      end

      def maybe_fallback_based_on_mt_simplify(options : Array({Symbol, Inner})) : Inner
        Fallback.build(self, @meta_type, options)
      end

      def final_mt_simplify(ctx : Context) : Inner
        Terminal.new(meta_type.simplify(ctx))
      end
    end

    struct Decision < Inner
      getter key : Key
      getter map : Hash(MetaType, Inner)
      def initialize(@key, @map)
      end

      def self.build(key, map)
        raise ArgumentError.new("empty decision") if map.empty?

        first_inner = map.values.first
        return first_inner if map.values.all?(&.==(first_inner))

        new(key, map)
      end

      def pretty_print(format : PrettyPrint)
        format.group do
          format.text(key.to_s)
          format.surround(" : {", " }", left_break: " ", right_break: nil) do
            @map.each_with_index do |pair, index|
              value, inner = pair

              format.breakable ", " if index != 0
              format.group do
                value.inner.pretty_print(format)
                format.text " => "
                format.nest do
                  inner.pretty_print(format)
                end
              end
            end
          end
        end
      end

      def any_error? : Bool
        map.values.any?(&.any_error?)
      end

      def total_error : Error?
        errors = [] of {Source::Pos, String, Array(Error::Info)}

        key = @key
        key_pos = key.is_a?(Info) ? key.pos : Source::Pos.none
        key_describe =
          case key
          when Info; "this #{key.describe_kind}"
          when :f_cap; "the function receiver capability"
          else raise NotImplementedError.new(key)
          end

        map.to_a.compact_map do |mt, inner|
          inner_err = inner.total_error
          next unless inner_err
          {"#{key_describe} may have type #{mt.show_type}", inner_err}
        end.reduce(nil) do |accum, (key_message, inner_err)|
          if accum
            Error.new(accum.pos, accum.headline).tap do |total|
              total.info.concat(accum.info)
              total.info << {key_pos, key_message}
              total.info.concat(inner_err.info)
            end
          else
            Error.new(inner_err.pos, inner_err.headline).tap do |total|
              total.info << {key_pos, key_message}
              total.info.concat(inner_err.info)
            end
          end
        end
      end

      def has_key?(key : Key) : Bool
        @key == key || map.values.any?(&.has_key?(key))
      end

      def gather_all_keys(set = Set(Key).new) : Set(Key)
        set.add(@key)
        map.values.each(&.gather_all_keys(set))
        set
      end

      def all_terminal_meta_types : Array(MetaType)
        map.values.flat_map(&.all_terminal_meta_types)
      end

      def any_mt?(&block : MetaType -> Bool) : Bool
        map.values.any?(&.any_mt?(&block))
      end

      def transform_mt(&block : MetaType -> MetaType) : Inner
        Decision.build(@key, @map.transform_values(&.transform_mt(&block)))
      end

      def transform_mt_using(key : Key, maybe_value : MetaType?, &block : (MetaType, MetaType?) -> MetaType) : Inner
        Decision.build(@key,
          if @key == key
            @map.map do |value, inner|
              {value, inner.transform_mt_using(key, value, &block)}
            end.to_h
          else
            @map.transform_values(&.transform_mt_using(key, maybe_value, &block))
          end
        )
      end

      def decided_by(key : Key, orig_keys : Set(Key), &block : MetaType -> Enumerable({MetaType, Span})) : Inner
        raise NotImplementedError.new("decision key conflict") if @key == key
        Decision.build(@key, @map.transform_values(&.decided_by(key, orig_keys, &block)))
      end

      def combine_mt_to_span(other : Inner, maybe_other_terminal : Terminal?, &block : (MetaType, MetaType) -> Span) : Inner
        if maybe_other_terminal
          Decision.build(@key, @map.transform_values(&.combine_mt_to_span(other, maybe_other_terminal, &block).as(Inner)))
        else
          if other.is_a?(Terminal)
            swap_block = -> (b : MetaType, a : MetaType) { block.call(a, b) }
            return other.combine_mt_to_span(self, nil, &swap_block)
          else
            raise NotImplementedError.new("combine_mt_to_span for a decision and another non-terminal")
          end
        end
      end

      def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Inner?
        if @key == :f_cap
          exact_inner = @map[f_cap_mt]?
          return exact_inner if exact_inner

          @map.find do |value, inner|
            f_cap_mt.cap_only_inner.subtype_of?(value.not_nil!.cap_only_inner) ||
            f_cap_mt.inner == MetaType::Capability::ISO || # TODO: better way to handle auto recovery
            f_cap_mt.inner == MetaType::Capability::TRN || # TODO: better way to handle auto recovery
            is_constructor # TODO: better way to do this?
          end.try(&.last)
        else
          Decision.build(@key,
            @map.transform_values do |inner|
              new_inner = inner.deciding_f_cap(f_cap_mt, is_constructor)
              return nil unless new_inner
              new_inner
            end
          )
        end
      end

      def maybe_fallback_based_on_mt_simplify(options : Array({Symbol, Inner})) : Inner
        Decision.build(@key, @map.transform_values(&.maybe_fallback_based_on_mt_simplify(options)))
      end

      def final_mt_simplify(ctx : Context) : Inner
        Decision.build(@key, @map.transform_values(&.final_mt_simplify(ctx)))
      end
    end

    struct Fallback < Inner
      getter default : StructRef(Inner)
      getter evaluate_mt : MetaType
      getter options : Array({Symbol, Inner})
      def initialize(@default, @evaluate_mt, @options)
      end

      def self.build(default : Inner, evaluate_mt, options)
        # If no fallback options were given, just use the default node.
        return default if options.empty?

        # If all options are the same as default, just use the default node.
        return default if options.all?(&.last.==(default))

        # Otherwise, build the node as requested.
        new(StructRef(Inner).new(default), evaluate_mt, options)
      end

      def pretty_print(format : PrettyPrint)
        format.group do
          @evaluate_mt.inner.pretty_print(format)
          format.surround(" ?: {", " }", left_break: " ", right_break: nil) do
            @options.each do |(cond, inner)|
              format.group do
                cond.pretty_print(format)
                format.text " => "
                format.nest do
                  inner.pretty_print(format)
                end
              end
              format.breakable ", "
            end
            format.text "_ => "
            format.nest do
              @default.value.pretty_print(format)
            end
          end
        end
      end

      def any_error? : Bool
        @default.value.any_error? || @options.any?(&.last.any_error?)
      end

      def total_error : Error?
        raise NotImplementedError.new("total_error for Fallback")
      end

      def has_key?(key : Key) : Bool
        @default.value.has_key?(key) || @options.any?(&.last.has_key?(key))
      end

      def gather_all_keys(set = Set(Key).new) : Set(Key)
        @default.value.gather_all_keys(set)
        @options.each(&.last.gather_all_keys(set))
        set
      end

      def all_terminal_meta_types : Array(MetaType)
        @default.value.all_terminal_meta_types + @options.flat_map(&.last.all_terminal_meta_types)
      end

      def any_mt?(&block : MetaType -> Bool) : Bool
        @default.value.any_mt?(&block) || @options.any?(&.last.any_mt?(&block))
      end

      def transform_mt(&block : MetaType -> MetaType) : Inner
        Fallback.build(
          @default.value.transform_mt(&block),
          @evaluate_mt,
          @options.map { |(cond, inner)| {cond, inner.transform_mt(&block)} }
        )
      end

      def transform_mt_using(key : Key, maybe_value : MetaType?, &block : (MetaType, MetaType?) -> MetaType) : Inner
        Fallback.build(
          @default.value.transform_mt_using(key, maybe_value, &block),
          @evaluate_mt,
          @options.map { |(cond, inner)| {cond, inner.transform_mt_using(key, maybe_value, &block)} }
        )
      end

      def decided_by(key : Key, orig_keys : Set(Key), &block : MetaType -> Enumerable({MetaType, Span})) : Inner
        Fallback.build(
          @default.value.decided_by(key, orig_keys, &block),
          @evaluate_mt,
          @options.map { |(cond, inner)| {cond, inner.decided_by(key, orig_keys, &block)} }
        )
      end

      def combine_mt_to_span(other : Inner, maybe_other_terminal : Terminal?, &block : (MetaType, MetaType) -> Span) : Inner
        if maybe_other_terminal
          Fallback.build(
            @default.value.combine_mt_to_span(other, maybe_other_terminal, &block),
            @evaluate_mt,
            @options.map { |(cond, inner)| {cond, inner.combine_mt_to_span(other, maybe_other_terminal, &block).as(Inner)} }
          )
        else
          if other.is_a?(Terminal)
            swap_block = -> (b : MetaType, a : MetaType) { block.call(a, b) }
            return other.combine_mt_to_span(self, nil, &swap_block)
          else
            raise NotImplementedError.new("combine_mt_to_span for a fallback and another non-terminal")
          end
        end
      end

      def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Inner?
        new_default = @default.value.deciding_f_cap(f_cap_mt, is_constructor)
        raise NotImplementedError.new("new_default missing in Fallback.build") \
          unless new_default

        Fallback.build(
          new_default,
          @evaluate_mt,
          @options.map { |(cond, inner)|
            new_inner = inner.deciding_f_cap(f_cap_mt, is_constructor)
            raise NotImplementedError.new("new_inner missing in Fallback.build") \
              unless new_inner

            {cond, new_inner}
          }
        )
      end

      def maybe_fallback_based_on_mt_simplify(other_options : Array({Symbol, Inner})) : Inner
        Fallback.build(
          @default.value.maybe_fallback_based_on_mt_simplify(other_options),
          @evaluate_mt,
          @options.map { |(cond, inner)| {cond, inner.maybe_fallback_based_on_mt_simplify(other_options)} }
        )
      end

      def final_mt_simplify(ctx : Context) : Inner
        evaluate_mt = @evaluate_mt.simplify(ctx)

        # Find the fallback option for which the evaluated MetaType matches
        # the associated condition, if any. If none match, use the default.
        @options.find { |(cond, inner)|
          case cond
          when :mt_unsatisfiable
            evaluate_mt.unsatisfiable?
          when :mt_non_singular_concrete
            !(evaluate_mt.singular? && evaluate_mt.single!.link.is_concrete?)
          else
            raise NotImplementedError.new(cond)
          end
        }
        .try(&.last.final_mt_simplify(ctx)) \
        || @default.final_mt_simplify(ctx)
      end
    end

    # This kind of Span::Inner "poisons" a Span with an error,
    # such that any further span operations only propagate that error.
    struct ErrorPropagate < Inner
      getter error : Error
      def initialize(@error)
      end

      def any_error? : Bool
        true
      end

      def total_error : Error?
        error
      end

      def has_key?(key : Key) : Bool
        false
      end

      def gather_all_keys(set = Set(Key).new) : Set(Key)
        set
      end

      def all_terminal_meta_types : Array(MetaType)
        [] of MetaType
      end

      def any_mt?(&block : MetaType -> Bool) : Bool
        false
      end

      def transform_mt(&block : MetaType -> MetaType) : Inner
        self
      end

      def transform_mt_using(key : Key, maybe_value : MetaType?, &block : (MetaType, MetaType?) -> MetaType) : Inner
        self
      end

      def decided_by(key : Key, orig_keys : Set(Key), &block : MetaType -> Enumerable({MetaType, Span})) : Inner
        self
      end

      def combine_mt_to_span(other : Inner, maybe_other_terminal : Terminal?, &block : (MetaType, MetaType) -> Span) : Inner
        self
      end

      def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Inner?
        self
      end

      def maybe_fallback_based_on_mt_simplify(options : Array({Symbol, Inner})) : Inner
        self
      end

      def final_mt_simplify(ctx : Context) : Inner
        self
      end
    end
  end

  struct Analysis
    def initialize
      @spans = {} of Infer::Info => Span
    end

    def [](info : Infer::Info); @spans[info]; end
    def []?(info : Infer::Info); @spans[info]?; end
    protected def []=(info, span); @spans[info] = span; end
  end

  class Visitor < Mare::AST::Visitor
    getter analysis
    protected getter func
    protected getter link
    protected getter refer_type
    protected getter refer_type_parent
    protected getter classify
    protected getter pre_infer

    protected def f_analysis; pre_infer; end # TODO: remove this alias

    def initialize(
      @func : Program::Function,
      @link : Program::Function::Link,
      @analysis : Analysis,
      @refer_type : ReferType::Analysis,
      @refer_type_parent : ReferType::Analysis,
      @classify : Classify::Analysis,
      @type_context : TypeContext::Analysis,
      @pre_infer : PreInfer::Analysis,
    )
      @substs_for_layer = Hash(TypeContext::Layer, Hash(Infer::TypeParam, Infer::MetaType)).new
    end

    def resolve(ctx : Context, info : Infer::Info) : Span
      @analysis[info]? || begin
        ast = @pre_infer.node_for?(info)
        substs = substs_for_layer(ctx, ast) if ast

        # If this info resolves as a conduit, resolve the conduit,
        # and do not save the result locally for this span.
        conduit = info.as_conduit?
        return conduit.resolve_span!(ctx, self) if conduit

        span = info.resolve_span!(ctx, self)
        span = span.transform_mt(&.substitute_type_params(substs.not_nil!)) if substs

        @analysis[info] = span

        span
      rescue Compiler::Pass::Analyze::ReentranceError
        kind = info.is_a?(Infer::DynamicInfo) ? " #{info.describe_kind}" : ""
        Error.at info.pos,
          "This#{kind} needs an explicit type; it could not be inferred"
      end
    end

    def type_params_for(ctx : Context, type_link : Program::Type::Link) : Array(Infer::TypeParam)
      type_link.resolve(ctx).params.try(&.terms.map { |type_param|
        ident = AST::Extract.type_param(type_param).first
        ref = refer_type[ident]? || refer_type_parent[ident]
        Infer::TypeParam.new(ref.as(Refer::TypeParam))
      }) || [] of Infer::TypeParam
    end

    def lookup_type_param_bound(ctx : Context, type_param : Infer::TypeParam)
      ref = type_param.ref
      raise "lookup on wrong visitor" unless ref.parent_link == link.type
      span = type_expr_span(ctx, ref.bound)
      MetaType.new_union(span.all_terminal_meta_types) # TODO: return a proper span instead of dumb union MetaType
    end

    def substs_for(ctx : Context, rt : Infer::ReifiedType) : Hash(Infer::TypeParam, Infer::MetaType)
      type_params_for(ctx, rt.link).zip(rt.args).to_h
    end

    def substs_for_layer(ctx : Context, node : AST::Node) : Hash(Infer::TypeParam, Infer::MetaType)?
      layer = @type_context[node]?
      return nil unless layer

      @substs_for_layer[layer] ||= (
        # TODO: also handle negative conditions
        layer.all_positive_conds.compact_map do |cond|
          cond_info = @pre_infer[cond]
          case cond_info
          when Infer::TypeParamCondition
            type_param = Infer::TypeParam.new(cond_info.refine)
            # TODO: carry through entire span, not just union of its MetaTypes
            meta_type = Infer::MetaType.new_type_param(type_param).intersect(
              Infer::MetaType.new_union(
                resolve(ctx, cond_info.refine_type).all_terminal_meta_types
              )
            )
            {type_param, meta_type}
          # TODO: also handle other conditions?
          else nil
          end
        end.to_h
      )
    end

    def depends_on_call_ret_span(ctx, other_rt, other_f, other_f_link)
      deps = ctx.alt_infer_edge.gather_deps_for_func(ctx, other_f, other_f_link)
      visitor = Visitor.new(other_f, other_f_link, Analysis.new, *deps)

      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = deps.last
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      other_analysis[other_pre[other_f.ident]]
      .transform_mt(&.substitute_type_params(visitor.substs_for(ctx, other_rt)))
    end

    def depends_on_call_param_span(ctx, other_rt, other_f, other_f_link, index)
      deps = ctx.alt_infer_edge.gather_deps_for_func(ctx, other_f, other_f_link)
      visitor = Visitor.new(other_f, other_f_link, Analysis.new, *deps)

      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = deps.last
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      other_analysis[other_pre[AST::Extract.params(other_f.params)[index].first]]
      .transform_mt(&.substitute_type_params(visitor.substs_for(ctx, other_rt)))
    end

    def depends_on_call_yield_in_span(ctx, other_rt, other_f, other_f_link)
      deps = ctx.alt_infer_edge.gather_deps_for_func(ctx, other_f, other_f_link)
      visitor = Visitor.new(other_f, other_f_link, Analysis.new, *deps)

      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = deps.last
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      other_analysis[other_pre.yield_in_info.not_nil!]
      .transform_mt(&.substitute_type_params(visitor.substs_for(ctx, other_rt)))
    end

    def depends_on_call_yield_out_span(ctx, other_rt, other_f, other_f_link, index)
      deps = ctx.alt_infer_edge.gather_deps_for_func(ctx, other_f, other_f_link)
      visitor = Visitor.new(other_f, other_f_link, Analysis.new, *deps)

      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = deps.last
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      other_analysis[other_pre.yield_out_infos[index]]
      .transform_mt(&.substitute_type_params(visitor.substs_for(ctx, other_rt)))
    end

    def run_edge(ctx : Context)
      func.params.try do |params|
        params.terms.each { |param| resolve(ctx, @pre_infer[param]) }
      end

      resolve(ctx, @pre_infer[ret])

      @pre_infer.yield_in_info.try { |info| resolve(ctx, info) }
      @pre_infer.yield_out_infos.each { |info| resolve(ctx, info) }
    end

    def run(ctx : Context)
      func_body = func.body
      resolve(ctx, @pre_infer[func_body]) if func_body

      @pre_infer.each_info { |info| resolve(ctx, info) }
    end

    def ret
      # The ident is used as a fake local variable that represents the return.
      func.ident
    end

    def prelude_reified_type(ctx : Context, name : String, args = [] of Infer::MetaType)
      Infer::ReifiedType.new(ctx.namespace.prelude_type(name), args)
    end

    def prelude_type_span(ctx : Context, name : String)
      Span.simple(Infer::MetaType.new(prelude_reified_type(ctx, name)))
    end

    def type_expr_cap(node : AST::Identifier) : Infer::MetaType::Capability
      case node.value
      when "iso", "trn", "val", "ref", "box", "tag", "non"
        Infer::MetaType::Capability.new(node.value)
      when "any", "alias", "send", "share", "read"
        Infer::MetaType::Capability.new_generic(node.value)
      else
        Error.at node, "This type couldn't be resolved"
      end
    end

    # An identifier type expression must refer to a type.
    def type_expr_span(ctx : Context, node : AST::Identifier) : Span
      ref = refer_type[node]?
      case ref
      when Refer::Self
        Span.self_with_reify_cap(ctx, self)
      when Refer::Type
        Span.simple(Infer::MetaType.new(Infer::ReifiedType.new(ref.link)))
      # when Refer::TypeAlias
      #   Infer::MetaType.new_alias(reified_type_alias(ref.link_alias))
      when Refer::TypeParam
        Span.simple(Infer::MetaType.new_type_param(Infer::TypeParam.new(ref)))
      when nil
        Span.simple(Infer::MetaType.new(type_expr_cap(node)))
      else
        raise NotImplementedError.new(ref.inspect)
      end
    end

    # An relate type expression must be an explicit capability qualifier.
    def type_expr_span(ctx : Context, node : AST::Relate) : Span
      if node.op.value == "'"
        cap_ident = node.rhs.as(AST::Identifier)
        case cap_ident.value
        when "aliased"
          type_expr_span(ctx, node.lhs).transform_mt do |lhs_mt|
            lhs_mt.alias
          end
        else
          cap = type_expr_cap(cap_ident)
          type_expr_span(ctx, node.lhs).transform_mt do |lhs_mt|
            lhs_mt.override_cap(cap)
          end
        end
      elsif node.op.value == "->"
        lhs = type_expr_span(ctx, node.lhs)
        rhs = type_expr_span(ctx, node.rhs)
        lhs.combine_mt(rhs) { |lhs_mt, rhs_mt| rhs_mt.viewed_from(lhs_mt) }
      elsif node.op.value == "->>"
        lhs = type_expr_span(ctx, node.lhs)
        rhs = type_expr_span(ctx, node.rhs)
        lhs.combine_mt(rhs) { |lhs_mt, rhs_mt| rhs_mt.extracted_from(lhs_mt) }
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "|" group must be a union of type expressions, and a "(" group is
    # considered to be just be a single parenthesized type expression (for now).
    def type_expr_span(ctx : Context, node : AST::Group) : Span
      if node.style == "|"
        spans = node.terms
          .select { |t| t.is_a?(AST::Group) && t.terms.size > 0 }
          .map { |t| type_expr_span(ctx, t).as(Span) }

        raise NotImplementedError.new("empty union") if spans.empty?

        Span.combine_mts(spans) { |mts| Infer::MetaType.new_union(mts) }.not_nil!
      elsif node.style == "(" && node.terms.size == 1
        type_expr_span(ctx, node.terms.first)
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "(" qualify is used to add type arguments to a type.
    def type_expr_span(ctx : Context, node : AST::Qualify) : Span
      raise NotImplementedError.new(node.to_a) unless node.group.style == "("

      target_span = type_expr_span(ctx, node.term)
      arg_spans = node.group.terms.map do |t|
        type_expr_span(ctx, t).as(Span)
      end

      target_span.combine_mts(arg_spans) do |target_mt, arg_mts|
        target_inner = target_mt.inner
        if target_inner.is_a?(Infer::MetaType::Nominal) \
        && target_inner.defn.is_a?(Infer::ReifiedTypeAlias)
          link = target_inner.defn.as(Infer::ReifiedTypeAlias).link
          Infer::MetaType.new(Infer::ReifiedTypeAlias.new(link, arg_mts))
        else
          link = target_mt.single!.link
          cap = begin target_mt.cap_only rescue nil end
          mt = Infer::MetaType.new(Infer::ReifiedType.new(link, arg_mts))
          mt = mt.override_cap(cap) if cap
          mt
        end
      end
    end

    # All other AST nodes are unsupported as type expressions.
    def type_expr_span(ctx : Context, node : AST::Node) : Span
      raise NotImplementedError.new(node.to_a)
    end
  end

  # The "edge" version of the pass only resolves the minimal amount of nodes
  # needed to understand the type signature of each function in the program.
  class PassEdge < Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      deps = gather_deps_for_func(ctx, f, f_link)
      prev = ctx.prev_ctx.try(&.alt_infer_edge)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(f, f_link, Analysis.new, *deps).tap(&.run_edge(ctx)).analysis
      end
    end

    def gather_deps_for_func(ctx, f, f_link)
      refer_type = ctx.refer_type[f_link]
      refer_type_parent = ctx.refer_type[f_link.type]
      classify = ctx.classify[f_link]
      type_context = ctx.type_context[f_link]
      pre_infer = ctx.pre_infer[f_link]

      {refer_type, refer_type_parent, classify, type_context, pre_infer}
    end
  end

  # This pass picks up the Analysis wherever the PassEdge last left off,
  # resolving all of the other nodes that weren't reached in edge analysis.
  class Pass < Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      deps = gather_deps_for_func(ctx, f, f_link)
      prev = ctx.prev_ctx.try(&.alt_infer)

      edge_analysis = ctx.alt_infer_edge[f_link]
      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(f, f_link, edge_analysis, *deps).tap(&.run(ctx)).analysis
      end
    end

    def gather_deps_for_func(ctx, f, f_link)
      refer_type = ctx.refer_type[f_link]
      refer_type_parent = ctx.refer_type[f_link.type]
      classify = ctx.classify[f_link]
      type_context = ctx.type_context[f_link]
      pre_infer = ctx.pre_infer[f_link]

      {refer_type, refer_type_parent, classify, type_context, pre_infer}
    end
  end
end
