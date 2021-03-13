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
    alias Key = Info | Symbol | Infer::TypeParam

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

    def each_mt(&block : MetaType -> Nil) : Nil
      inner.each_mt(&block)
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
      Span.new(inner.combine_mt_to_span(other.inner, nil, true, &mt_block))
    end

    def reduce_combine_mts(spans : Array(Span), &block : (MetaType, MetaType) -> MetaType) : Span
      case spans.size
      when 0; self
      when 1; combine_mt(spans.last, &block)
      else
        spans.reduce(self) { |span, other_span|
          span.combine_mt(other_span, &block)
        }
      end
    end

    def self.reduce_combine_mts(spans : Array(Span), &block : (MetaType, MetaType) -> MetaType) : Span?
      case spans.size
      when 0; nil
      when 1; spans.first
      when 2
        spans.first.combine_mt(spans.last, &block)
      else
        spans[1..-1].reduce(spans.first) { |span, other_span|
          span.combine_mt(other_span, &block)
        }
      end
    end

    def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Span?
      inner.deciding_f_cap(f_cap_mt, is_constructor)
      .try { |new_inner| Span.new(new_inner) }
    end

    def deciding_type_param(type_param : Infer::TypeParam, cap : MetaType) : Span?
      inner.deciding_type_param(type_param, cap)
      .try { |new_inner| Span.new(new_inner) }
    end

    def narrowing_type_param(type_param : Infer::TypeParam, cap : MetaType) : Span?
      inner.narrowing_type_param(type_param, cap)
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
      abstract def each_mt(&block : MetaType -> Nil) : Nil
      abstract def transform_mt(&block : MetaType -> MetaType) : Inner
      abstract def transform_mt_using(key : Key, maybe_value : MetaType?, &block : (MetaType, MetaType?) -> MetaType) : Inner
      abstract def decided_by(key : Key, orig_keys : Set(Key), &block : MetaType -> Enumerable({MetaType, Span})) : Inner
      abstract def combine_mt_to_span(other : Inner, maybe_other_terminal : Terminal?, always_yields_terminal = false, &block : (MetaType, MetaType) -> Span) : Inner
      abstract def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Inner?
      abstract def deciding_type_param(type_param : Infer::TypeParam, cap : MetaType) : Inner?
      abstract def narrowing_type_param(type_param : Infer::TypeParam, cap : MetaType) : Inner?
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

      def each_mt(&block : MetaType -> Nil) : Nil
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

      def combine_mt_to_span(other : Inner, maybe_other_terminal : Terminal?, always_yields_terminal = false, &block : (MetaType, MetaType) -> Span) : Inner
        if maybe_other_terminal
          block.call(self.meta_type, maybe_other_terminal.meta_type).inner
        else
          swap_block = -> (b : MetaType, a : MetaType) { block.call(a, b) }
          other.combine_mt_to_span(self, self, &swap_block)
        end
      end

      def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Inner?
        self # a terminal node ignores further decisions
      end

      def deciding_type_param(type_param : Infer::TypeParam, cap : MetaType) : Inner?
        self # a terminal node ignores further decisions
      end

      def narrowing_type_param(type_param : Infer::TypeParam, cap : MetaType) : Inner?
        self # a terminal node ignores further decisions
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

      def each_mt(&block : MetaType -> Nil) : Nil
        map.values.each(&.each_mt(&block))
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

      def combine_mt_to_span(other : Inner, maybe_other_terminal : Terminal?, always_yields_terminal = false, &block : (MetaType, MetaType) -> Span) : Inner
        if maybe_other_terminal
          Decision.build(@key, @map.transform_values(&.combine_mt_to_span(other, maybe_other_terminal, always_yields_terminal, &block).as(Inner)))
        else
          if other.is_a?(Terminal)
            swap_block = -> (b : MetaType, a : MetaType) { block.call(a, b) }
            return other.combine_mt_to_span(self, nil, always_yields_terminal, &swap_block)
          elsif other.is_a?(Decision) && other.key != @key \
            && @map.values.all?(&.is_a?(Terminal)) \
            && other.map.values.all?(&.is_a?(Terminal))
            # This is one easy special case we can handle right now.
            # We easily handle it because we don't need to do any merging keys.
            Decision.build(@key, @map.transform_values(&.combine_mt_to_span(other, nil, always_yields_terminal, &block).as(Inner)))
          elsif other.is_a?(Decision) && other.key == @key \
            && other.map.keys.all? { |other_value| @map.has_key?(other_value) }
            # Here's another simple case. We have the same key and a map with
            # all the same values, so we can trivially merge them pairwise.
            Decision.build(@key, @map.map { |value, inner|
              {value, inner.combine_mt_to_span(other.map[value], nil, always_yields_terminal, &block)}
              .as({MetaType, Inner})
            }.to_h)
          elsif @map.all? { |value, inner|
            inner.is_a?(Decision) && other.is_a?(Decision) \
            && other.key == inner.key \
            && other.map.keys.all? { |other_value| inner.map.has_key?(other_value) } \
            && other.map.values.all? { |other_inner| other_inner.is_a?(Terminal) }
          }
            # This is getting a bit ridiculous! We need to write the code that
            # handles the general case, but this is a special case we handle.
            Decision.build(@key, @map.transform_values(&.combine_mt_to_span(other, nil, always_yields_terminal, &block).as(Inner)))
          elsif always_yields_terminal \
            && (other_keys = other.gather_all_keys; true) \
            && gather_all_keys.all? { |key| !other_keys.includes?(key) }
            # If we know we have no overlapping keys, we can descend to the next level.
            Decision.build(@key, @map.transform_values(&.combine_mt_to_span(other, nil, always_yields_terminal, &block).as(Inner)))
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

      def deciding_type_param(type_param : Infer::TypeParam, cap : MetaType) : Inner?
        key = @key
        if key.is_a?(Infer::TypeParam) && key == type_param
          @map[cap]?
        else
          Decision.build(@key,
            @map.transform_values do |inner|
              new_inner = inner.deciding_type_param(type_param, cap)
              return nil unless new_inner
              new_inner
            end
          )
        end
      end

      def narrowing_type_param(type_param : Infer::TypeParam, cap : MetaType) : Inner?
        key = @key
        if key.is_a?(Infer::TypeParam) && key == type_param
          new_map = @map.select { |value, inner|
            value.cap_only_inner.satisfies_bound?(cap.cap_only_inner)
          }.to_h
          return nil unless new_map

          Decision.build(@key, new_map)
        else
          Decision.build(@key,
            @map.transform_values do |inner|
              new_inner = inner.narrowing_type_param(type_param, cap)
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

      def each_mt(&block : MetaType -> Nil) : Nil
        @default.value.each_mt(&block)
        @options.each(&.last.each_mt(&block))
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

      def combine_mt_to_span(other : Inner, maybe_other_terminal : Terminal?, always_yields_terminal = false, &block : (MetaType, MetaType) -> Span) : Inner
        if maybe_other_terminal
          Fallback.build(
            @default.value.combine_mt_to_span(other, maybe_other_terminal, always_yields_terminal, &block),
            @evaluate_mt,
            @options.map { |(cond, inner)| {cond, inner.combine_mt_to_span(other, maybe_other_terminal, always_yields_terminal, &block).as(Inner)} }
          )
        elsif !other.is_a?(Fallback)
          swap_block = -> (b : MetaType, a : MetaType) { block.call(a, b) }
          return other.combine_mt_to_span(self, nil, always_yields_terminal, &swap_block)
        elsif other.is_a?(Fallback) && \
          other.evaluate_mt == self.evaluate_mt && \
          other.options.map(&.first) == self.options.map(&.first)

          Fallback.build(
            @default.value.combine_mt_to_span(other.default.value, nil, always_yields_terminal, &block),
            @evaluate_mt,
            @options.map { |(cond, inner)|
              other_inner = other.options.find(&.first.==(cond)).not_nil!.last
              {cond, inner.combine_mt_to_span(other_inner, nil, always_yields_terminal, &block).as(Inner)}
            }
          )
        else
          raise NotImplementedError.new("combine_mt_to_span for two unlike fallbacks")
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

      def deciding_type_param(type_param : Infer::TypeParam, cap : MetaType) : Inner?
        new_default = @default.value.deciding_type_param(type_param, cap)
        raise NotImplementedError.new("new_default missing in Fallback.build") \
          unless new_default

        Fallback.build(
          new_default,
          @evaluate_mt,
          @options.map { |(cond, inner)|
            new_inner = inner.deciding_type_param(type_param, cap)
            raise NotImplementedError.new("new_inner missing in Fallback.build") \
              unless new_inner

            {cond, new_inner}
          }
        )
      end

      def narrowing_type_param(type_param : Infer::TypeParam, cap : MetaType) : Inner?
        new_default = @default.value.narrowing_type_param(type_param, cap)
        raise NotImplementedError.new("new_default missing in Fallback.build") \
          unless new_default

        Fallback.build(
          new_default,
          @evaluate_mt,
          @options.map { |(cond, inner)|
            new_inner = inner.narrowing_type_param(type_param, cap)
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

      def each_mt(&block : MetaType -> Nil) : Nil
        nil
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

      def combine_mt_to_span(other : Inner, maybe_other_terminal : Terminal?, always_yields_terminal = false, &block : (MetaType, MetaType) -> Span) : Inner
        self
      end

      def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Inner?
        self
      end

      def deciding_type_param(type_param : Infer::TypeParam, cap : MetaType) : Inner?
        self
      end

      def narrowing_type_param(type_param : Infer::TypeParam, cap : MetaType) : Inner?
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

  abstract struct Analysis
    def initialize
      @spans = {} of Infer::Info => Span
    end

    def [](info : Infer::Info); @spans[info]; end
    def []?(info : Infer::Info); @spans[info]?; end
    protected def []=(info, span); @spans[info] = span; end

    getter! type_params : Array(Infer::TypeParam)
    protected setter type_params

    def type_param_substs(type_args : Array(MetaType)) : Hash(Infer::TypeParam, Infer::MetaType)
      type_params.zip(type_args.map(&.strip_cap)).to_h
    end

    def deciding_type_args_of(
      ctx : Context,
      args : Array(Infer::MetaType),
      raw_span : Span
    ) : Span
      return raw_span if args.empty?

      # Many spans are simple terminals, so we can optimize things a bit here
      # by skipping the rest of this deciding when there is nothing to decide
      # because terminals have no decisions to be made.
      return raw_span if raw_span.inner.is_a?(Span::Terminal)

      type_params.zip(args).reduce(raw_span) { |span, (type_param, type_arg)|
        next unless span

        # When a type argument is passed from a raw type param,
        # we do not decide the capability here, because the type param
        # does not necessarily have just one capability.
        # TODO: Should we figure out how to combine the spans in some way
        # to make at least a span-contingent decision here?
        next span if type_arg.type_param_only?

        span.deciding_type_param(type_param, type_arg.cap_only)
      }
      .not_nil!
    end
  end

  struct FuncAnalysis < Analysis
  end

  struct TypeAnalysis < Analysis
  end

  struct TypeAliasAnalysis < Analysis
    getter! target_span : Span
    protected def target_span=(span : Span); @target_span = span; end
  end

  abstract class TypeExprEvaluator
    abstract def t_link : (Program::Type::Link | Program::TypeAlias::Link)

    abstract def refer_type_for(node : AST::Node) : Refer::Info?
    abstract def self_type_expr_span(ctx : Context) : Span

    def type_expr_cap(node : AST::Identifier) : Infer::MetaType::Capability?
      case node.value
      when "iso", "trn", "val", "ref", "box", "tag", "non"
        Infer::MetaType::Capability.new(node.value)
      when "any", "alias", "send", "share", "read"
        Infer::MetaType::Capability.new_generic(node.value)
      else
        nil
      end
    end

    # An identifier type expression must refer to a type.
    def type_expr_span(ctx : Context, node : AST::Identifier) : Span
      ref = refer_type_for(node)
      case ref
      when Refer::Self
        self_type_expr_span(ctx)
      when Refer::Type
        Span.simple(Infer::MetaType.new(Infer::ReifiedType.new(ref.link)))
      when Refer::TypeAlias
        Span.simple(Infer::MetaType.new_alias(Infer::ReifiedTypeAlias.new(ref.link_alias)))
      when Refer::TypeParam
        lookup_type_param_partial_reified_span(ctx, Infer::TypeParam.new(ref))
      when nil
        cap = type_expr_cap(node)
        if cap
          Span.simple(Infer::MetaType.new(cap))
        else
          Span.error node, "This type couldn't be resolved"
        end
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
          if cap
            type_expr_span(ctx, node.lhs).transform_mt do |lhs_mt|
              lhs_mt.override_cap(cap.not_nil!)
            end
          else
            Span.error cap_ident, "This type couldn't be resolved"
          end
        end
      elsif node.op.value == "->"
        lhs = type_expr_span(ctx, node.lhs).transform_mt(&.cap_only)
        rhs = type_expr_span(ctx, node.rhs)
        lhs.combine_mt(rhs) { |lhs_mt, rhs_mt| rhs_mt.viewed_from(lhs_mt) }
      elsif node.op.value == "->>"
        lhs = type_expr_span(ctx, node.lhs).transform_mt(&.cap_only)
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

        Span.reduce_combine_mts(spans) { |accum, mt| accum.unite(mt) }.not_nil!
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

      Span.reduce_combine_mts([target_span] + arg_spans) { |target_mt, arg_mt|
        cap = begin target_mt.cap_only rescue nil end

        target_inner = target_mt.inner
        mt =
          if target_inner.is_a?(Infer::MetaType::Nominal) \
          && target_inner.defn.is_a?(Infer::ReifiedTypeAlias)
            rta = target_inner.defn.as(Infer::ReifiedTypeAlias)
            arg_mts = rta.args + [arg_mt]
            Infer::MetaType.new(Infer::ReifiedTypeAlias.new(rta.link, arg_mts))
          # elsif target_inner.is_a?(Infer::MetaType::Nominal) \
          # && target_inner.defn.is_a?(Infer::TypeParam)
          #   # TODO: Some kind of ReifiedTypeParam monstrosity, to represent
          #   # an unknown type param invoked with type arguments?
          else
            rt = target_mt.single!
            arg_mts = rt.args + [arg_mt]
            Infer::MetaType.new(Infer::ReifiedType.new(rt.link, arg_mts))
          end

        mt = mt.override_cap(cap) if cap
        mt
      }.not_nil!
    end

    # All other AST nodes are unsupported as type expressions.
    def type_expr_span(ctx : Context, node : AST::Node) : Span
      raise NotImplementedError.new(node.to_a)
    end

    @currently_looking_up_param_bounds = Set(Infer::TypeParam).new
    def lookup_type_param_bound_span(ctx : Context, type_param : Infer::TypeParam)
      @currently_looking_up_param_bounds.add(type_param)

      ref = type_param.ref
      raise "lookup on wrong visitor" unless ref.parent_link == t_link
      type_expr_span(ctx, ref.bound)

      .tap { @currently_looking_up_param_bounds.delete(type_param) }
    end
    def lookup_type_param_partial_reified_span(ctx : Context, type_param : Infer::TypeParam)
      # Avoid infinite recursion by taking a lazy approach if we are already
      # recursed into this type param's bound resolution.
      # This lazy reference can be unwrapped by other logic later as needed.
      if @currently_looking_up_param_bounds.includes?(type_param)
        lazy = Infer::TypeParam.new(type_param.ref)
        lazy.lazy = true
        return Span.simple(MetaType.new_type_param(lazy))
      end

      # Otherwise, continue by looking up the bound of this type param,
      # and intersect it with the type param reference itself, expanding the
      # span to include every possible single cap instead of using a multi-cap.
      lookup_type_param_bound_span(ctx, type_param).decided_by(type_param) { |bound_mt|
        bound_mt.cap_only_inner.each_cap.map { |cap|
          cap_mt = MetaType.new(cap)
          mt = MetaType
            .new_type_param(type_param)
            .intersect(cap_mt)
            # .intersect(bound_mt.strip_cap)
          # TODO: Introduce a Fact Span that adds the bound_mt as a fact?
          {cap_mt, Span.simple(mt)}
        }.to_h
      }
    end
  end

  class TypeVisitor < TypeExprEvaluator
    getter analysis

    def initialize(
      @type : Program::Type,
      @link : Program::Type::Link,
      @analysis : TypeAnalysis,
      @refer_type : ReferType::Analysis
    )
      @analysis.type_params =
        @type.params.try(&.terms.map { |type_param|
          ident = AST::Extract.type_param(type_param).first
          ref = refer_type_for(ident)
          Infer::TypeParam.new(ref.as(Refer::TypeParam))
        }) || [] of Infer::TypeParam
    end

    def run(ctx)
    end

    def t_link : (Program::Type::Link | Program::TypeAlias::Link)
      @link
    end

    def refer_type_for(node : AST::Node) : Refer::Info?
      @refer_type[node]?
    end

    def self_type_expr_span(ctx : Context) : Span
      raise NotImplementedError.new("#{self.class} self_type_expr_span")
    end
  end

  class TypeAliasVisitor < TypeExprEvaluator
    getter analysis

    def initialize(
      @type_alias : Program::TypeAlias,
      @link : Program::TypeAlias::Link,
      @analysis : TypeAliasAnalysis,
      @refer_type : ReferType::Analysis
    )
      @analysis.type_params =
        @type_alias.params.try(&.terms.map { |type_param|
          ident = AST::Extract.type_param(type_param).first
          ref = refer_type_for(ident)
          Infer::TypeParam.new(ref.as(Refer::TypeParam))
        }) || [] of Infer::TypeParam
    end

    def run(ctx)
      @analysis.target_span = get_target_span(ctx)
    end

    private def get_target_span(ctx)
      target_span = type_expr_span(ctx, @type_alias.target)

      if target_span.all_terminal_meta_types.any? { |mt|
        is_directly_recursive = false
        mt.each_type_alias_in_first_layer { |rta|
          is_directly_recursive ||= rta.link == @link
        }
        is_directly_recursive
      }
        return Span.error @type_alias.ident.pos,
          "This type alias is directly recursive, which is not supported",
          [{@type_alias.target.pos,
            "only recursion via type arguments is supported in this expression"
          }]
      end

      target_span
    end

    def t_link : (Program::Type::Link | Program::TypeAlias::Link)
      @link
    end

    def refer_type_for(node : AST::Node) : Refer::Info?
      @refer_type[node]?
    end

    def self_type_expr_span(ctx : Context) : Span
      raise NotImplementedError.new("#{self.class} self_type_expr_span")
    end
  end

  class Visitor < TypeExprEvaluator
    getter analysis
    protected getter func
    protected getter link
    protected getter t_analysis
    protected getter refer_type
    protected getter refer_type_parent
    protected getter classify
    protected getter pre_infer

    protected def f_analysis; pre_infer; end # TODO: remove this alias

    def initialize(
      @func : Program::Function,
      @link : Program::Function::Link,
      @analysis : FuncAnalysis,
      @t_analysis : TypeAnalysis,
      @refer_type : ReferType::Analysis,
      @refer_type_parent : ReferType::Analysis,
      @classify : Classify::Analysis,
      @type_context : TypeContext::Analysis,
      @pre_infer : PreInfer::Analysis,
    )
      @analysis.type_params = @t_analysis.type_params
    end

    def t_link : (Program::Type::Link | Program::TypeAlias::Link)
      @link.type
    end

    def resolve(ctx : Context, info : Infer::Info) : Span
      @analysis[info]? || begin
        # If this info resolves as a conduit, resolve the conduit,
        # and do not save the result locally for this span.
        conduit = info.as_conduit?
        return conduit.resolve_span!(ctx, self) if conduit

        span = info.resolve_span!(ctx, self)

        # Deal with type parameter substitutions if needed.
        # This happens when we have a localized type refinement,
        # such as inside a conditional block with a type condition.
        span = apply_substs_for_layer(ctx, info, span)

        # substitute lazy type params if needed
        lazy_type_params = Set(Infer::TypeParam).new
        max_depth = 1
        span.each_mt { |mt|
          mt.gather_lazy_type_params_referenced(ctx, lazy_type_params, max_depth)
        }
        if lazy_type_params.any?
          span = lazy_type_params.reduce(span) { |span, type_param|
            type_param_span = lookup_type_param_partial_reified_span(ctx, type_param)

            span.combine_mt(type_param_span) { |mt, type_param_mt|
              mt.substitute_lazy_type_params({
                type_param => type_param_mt # MetaType.new_type_param(type_param).intersect(type_param_mt.cap_only)
              }, max_depth)
            }
          }
        end

        @analysis[info] = span

        span
      rescue Compiler::Pass::Analyze::ReentranceError
        kind = info.is_a?(Infer::DynamicInfo) ? " #{info.describe_kind}" : ""
        AltInfer::Span.error info.pos,
          "This#{kind} needs an explicit type; it could not be inferred"
      end
    end

    # TODO: remove this in favor of the span-returning function within.
    def lookup_type_param_bound(ctx : Context, type_param : Infer::TypeParam)
      span = lookup_type_param_bound_span(ctx, type_param)
      MetaType.new_union(span.all_terminal_meta_types)
    end

    def unwrap_lazy_parts_of_type_expr_span(ctx : Context, span : Span) : Span
      # Currently the only lazy part we handle here is type aliases.
      span.transform_mt { |mt|
        mt.substitute_each_type_alias_in_first_layer { |rta|
          other_analysis = ctx.alt_infer_edge.run_for_type_alias(ctx, rta.link.resolve(ctx), rta.link)
          span = other_analysis.deciding_type_args_of(ctx, rta.args, other_analysis.target_span)
            .transform_mt(&.substitute_type_params(other_analysis.type_param_substs(rta.args)))
          span_inner = span.inner

          # TODO: better way of dealing with ErrorPropagate, related to other TODO below:
          raise span_inner.error if span_inner.is_a?(Span::ErrorPropagate)

          # TODO: support dealing with the entire span instead of just asserting its singularity
          span_inner.as(Span::Terminal).meta_type
        }
      }
    rescue error : Error
      Span.new(Span::ErrorPropagate.new(error))
    end

    def apply_substs_for_layer(ctx : Context, info : Info, span : Span) : Span
      layer = @type_context[info.layer_index]

      # TODO: also handle negative conditions
      layer.all_positive_conds.reduce(span) { |span, cond|
        cond_info = @pre_infer[cond]
        case cond_info
        when Infer::TypeParamCondition
          type_param = Infer::TypeParam.new(cond_info.refine)
          refine_span = resolve(ctx, cond_info.refine_type)
          refine_cap_mt =
            Infer::MetaType.new_union(refine_span.all_terminal_meta_types.map(&.cap_only))
          raise NotImplementedError.new("varying caps in a refined span") unless refine_cap_mt.cap_only?

          span
            .narrowing_type_param(type_param, refine_cap_mt)
            .not_nil!
            .combine_mt(refine_span.narrowing_type_param(type_param, refine_cap_mt).not_nil!) { |mt, refine_mt|
              mt.substitute_type_params({
                type_param => Infer::MetaType.new_type_param(type_param).intersect(refine_mt.strip_cap)
              })
            }
        # TODO: also handle other conditions?
        else span
        end
      }
    end

    def refer_type_for(node : AST::Node) : Refer::Info?
      @refer_type[node]? || refer_type_parent[node]?
    end

    def self_with_no_cap_yet(ctx : Context)
      # Get the spans for each partially reified type param in this type.
      type_param_spans = @analysis.type_params.map { |type_param|
        lookup_type_param_partial_reified_span(ctx, type_param).as(Span)
      }

      # Combine the spans in all combinations of those partial reifications.
      # If there are no type params to combine, we just use a simple span.
      Span.simple(MetaType.new_nominal(ReifiedType.new(link.type)))
        .reduce_combine_mts(type_param_spans) { |accum_mt, arg_mt|
          rt = accum_mt.single!
          MetaType.new_nominal(ReifiedType.new(rt.link, rt.args + [arg_mt]))
        }
    end

    def self_type_expr_span(ctx : Context) : Span
      rt_span = self_with_no_cap_yet(ctx)

      # Finally, build the top of the span's decision tree with possible f_caps.
      f = self.func
      f_cap_value = f.cap.value
      f_cap_value = "ref" if f.has_tag?(:constructor)
      f_cap_value = "read" if f_cap_value == "box" # TODO: figure out if we can remove this Pony-originating semantic hack
      Span.decision(
        :f_cap,
        MetaType::Capability.new_maybe_generic(f_cap_value).each_cap.map do |cap|
          cap_mt = MetaType.new(cap)
          {cap_mt, rt_span.transform_mt(&.intersect(cap_mt))}
        end.to_h
      )
    end

    def self_ephemeral_with_cap(ctx : Context, cap : String)
      self_with_no_cap_yet(ctx)
        .transform_mt(&.intersect(MetaType.cap(cap)).ephemeralize)
    end

    def depends_on_call_ret_span(ctx, other_rt, other_f, other_f_link)
      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_infer[other_f_link]
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis[other_pre[other_f.ident]]

      other_analysis.deciding_type_args_of(ctx, other_rt.args, raw_span)
      .transform_mt(&.substitute_type_params(other_analysis.type_param_substs(other_rt.args)))
    end

    def depends_on_call_param_span(ctx, other_rt, other_f, other_f_link, index)
      param = AST::Extract.params(other_f.params)[index]?
      return unless param

      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_infer[other_f_link]
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis[other_pre[param.first]]

      other_analysis.deciding_type_args_of(ctx, other_rt.args, raw_span)
      .transform_mt(&.substitute_type_params(other_analysis.type_param_substs(other_rt.args)))
    end

    def depends_on_call_yield_in_span(ctx, other_rt, other_f, other_f_link)
      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_infer[other_f_link]
      yield_in_info = other_pre.yield_in_info
      return unless yield_in_info
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis[yield_in_info]

      other_analysis.deciding_type_args_of(ctx, other_rt.args, raw_span)
      .transform_mt(&.substitute_type_params(other_analysis.type_param_substs(other_rt.args)))
    end

    def depends_on_call_yield_out_span(ctx, other_rt, other_f, other_f_link, index)
      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = ctx.pre_infer[other_f_link]
      yield_out_info = other_pre.yield_out_infos[index]?
      return unless yield_out_info
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      raw_span = other_analysis[yield_out_info]

      other_analysis.deciding_type_args_of(ctx, other_rt.args, raw_span)
      .transform_mt(&.substitute_type_params(other_analysis.type_param_substs(other_rt.args)))
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
  end

  # The "edge" version of the pass only resolves the minimal amount of nodes
  # needed to understand the type signature of each function in the program.
  class PassEdge < Compiler::Pass::Analyze(TypeAliasAnalysis, TypeAnalysis, FuncAnalysis)
    def analyze_type_alias(ctx, t, t_link) : TypeAliasAnalysis
      refer_type = ctx.refer_type[t_link]
      deps = refer_type
      prev = ctx.prev_ctx.try(&.alt_infer_edge)

      maybe_from_type_alias_cache(ctx, prev, t, t_link, deps) do
        TypeAliasVisitor.new(t, t_link, TypeAliasAnalysis.new, refer_type).tap(&.run(ctx)).analysis
      end
    end

    def analyze_type(ctx, t, t_link) : TypeAnalysis
      refer_type = ctx.refer_type[t_link]
      deps = refer_type
      prev = ctx.prev_ctx.try(&.alt_infer_edge)

      maybe_from_type_cache(ctx, prev, t, t_link, deps) do
        TypeVisitor.new(t, t_link, TypeAnalysis.new, refer_type).tap(&.run(ctx)).analysis
      end
    end

    def analyze_func(ctx, f, f_link, t_analysis) : FuncAnalysis
      deps = gather_deps_for_func(ctx, f, f_link)
      prev = ctx.prev_ctx.try(&.alt_infer_edge)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(f, f_link, FuncAnalysis.new, t_analysis, *deps).tap(&.run_edge(ctx)).analysis
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

  # This pass picks up the FuncAnalysis wherever the PassEdge last left off,
  # resolving all of the other nodes that weren't reached in edge analysis.
  class Pass < Compiler::Pass::Analyze(TypeAliasAnalysis, TypeAnalysis, FuncAnalysis)
    def analyze_type_alias(ctx, t, t_link) : TypeAliasAnalysis
      ctx.alt_infer_edge[t_link]
    end

    def analyze_type(ctx, t, t_link) : TypeAnalysis
      ctx.alt_infer_edge[t_link]
    end

    def analyze_func(ctx, f, f_link, t_analysis) : FuncAnalysis
      deps = gather_deps_for_func(ctx, f, f_link)
      prev = ctx.prev_ctx.try(&.alt_infer)

      edge_analysis = ctx.alt_infer_edge[f_link]
      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(f, f_link, edge_analysis, t_analysis, *deps).tap(&.run(ctx)).analysis
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
