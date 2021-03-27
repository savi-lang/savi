module Mare::Compiler::Infer
  struct Span
    alias Key = Info | Symbol | TypeParam

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

    def transform_mt_to_span(&block : MetaType -> Span) : Span
      Span.new(inner.transform_mt_to_span([] of {Key, MetaType}, &block))
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

    def deciding_exact(key : Key, mt : MetaType) : Span?
      inner.deciding_exact(key, mt)
      .try { |new_inner| Span.new(new_inner) }
    end

    def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Span?
      inner.deciding_f_cap(f_cap_mt, is_constructor)
      .try { |new_inner| Span.new(new_inner) }
    end

    def deciding_type_param(type_param : TypeParam, cap : MetaType) : Span?
      inner.deciding_type_param(type_param, cap)
      .try { |new_inner| Span.new(new_inner) }
    end

    def narrowing_type_param(type_param : TypeParam, cap : MetaType) : Span?
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

    def final_mt!(ctx : Context) : MetaType?
      span = self.final_mt_simplify(ctx)

      if span.try(&.any_error?)
        ctx.errors << span.total_error.not_nil!
        return nil
      end

      inner = span.inner
      return inner.meta_type if inner.is_a?(Terminal)

      raise NotImplementedError.new(span.inspect)
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
      abstract def transform_mt_to_span(decided : Array({Key, MetaType}), &block : MetaType -> Span) : Inner
      abstract def decided_by(key : Key, orig_keys : Set(Key), &block : MetaType -> Enumerable({MetaType, Span})) : Inner
      abstract def combine_mt_to_span(other : Inner, maybe_other_terminal : Terminal?, always_yields_terminal = false, &block : (MetaType, MetaType) -> Span) : Inner
      abstract def deciding_exact(key : Key, mt : MetaType) : Inner?
      abstract def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Inner?
      abstract def deciding_type_param(type_param : TypeParam, cap : MetaType) : Inner?
      abstract def narrowing_type_param(type_param : TypeParam, cap : MetaType) : Inner?
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

      def transform_mt_to_span(decided : Array({Key, MetaType}), &block : MetaType -> Span) : Inner
        span = block.call(@meta_type)
        decided.each { |(key, mt)|
          span = span.deciding_exact(key, mt).not_nil! # TODO: how can we nicely handle this nil case?
        }
        span.inner
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

      def deciding_exact(key : Key, mt : MetaType) : Inner?
        self # a terminal node ignores further decisions
      end

      def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Inner?
        self # a terminal node ignores further decisions
      end

      def deciding_type_param(type_param : TypeParam, cap : MetaType) : Inner?
        self # a terminal node ignores further decisions
      end

      def narrowing_type_param(type_param : TypeParam, cap : MetaType) : Inner?
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

      def transform_mt_to_span(decided : Array({Key, MetaType}), &block : MetaType -> Span) : Inner
        Decision.build(@key, @map.map { |value, inner|
          {value, inner.transform_mt_to_span(decided + [{key, value}], &block)}
        }.to_h)
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
          elsif always_yields_terminal && !(other.gather_all_keys.includes?(@key))
            # If the other one does not ovelap with our immediate key,
            # we can descend to the next level and continue.
            Decision.build(@key, @map.transform_values(&.combine_mt_to_span(other, nil, always_yields_terminal, &block).as(Inner)))
          elsif other.is_a?(Decision) && \
            always_yields_terminal && !(gather_all_keys.includes?(other.key))
            # This is the inverse of the above condition.
            swap_block = -> (b : MetaType, a : MetaType) { block.call(a, b) }
            Decision.build(other.key, other.map.transform_values(&.combine_mt_to_span(self, nil, always_yields_terminal, &swap_block).as(Inner)))
          else
            raise NotImplementedError.new("combine_mt_to_span for a decision and another non-terminal")
          end
        end
      end

      def deciding_exact(key : Key, mt : MetaType) : Inner?
        if @key == key
          exact_inner = @map[mt]?
        else
          Decision.build(@key,
            @map.transform_values do |inner|
              new_inner = inner.deciding_exact(key, mt)
              return nil unless new_inner
              new_inner
            end
          )
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

      def deciding_type_param(type_param : TypeParam, cap : MetaType) : Inner?
        key = @key
        if key.is_a?(TypeParam) && key == type_param
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

      def narrowing_type_param(type_param : TypeParam, cap : MetaType) : Inner?
        key = @key
        if key.is_a?(TypeParam) && key == type_param
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

      def transform_mt_to_span(decided : Array({Key, MetaType}), &block : MetaType -> Span) : Inner
        Fallback.build(
          @default.value.transform_mt_to_span(decided, &block),
          @evaluate_mt,
          @options.map { |(cond, inner)|
            {cond, inner.transform_mt_to_span(decided, &block)}
          }
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

      def deciding_exact(key : Key, mt : MetaType) : Inner?
        new_default = @default.value.deciding_exact(key, mt)
        raise NotImplementedError.new("new_default missing in Fallback.build") \
          unless new_default

        Fallback.build(
          new_default,
          @evaluate_mt,
          @options.map { |(cond, inner)|
            new_inner = inner.deciding_exact(key, mt)
            raise NotImplementedError.new("new_inner missing in Fallback.build") \
              unless new_inner

            {cond, new_inner}
          }
        )
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

      def deciding_type_param(type_param : TypeParam, cap : MetaType) : Inner?
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

      def narrowing_type_param(type_param : TypeParam, cap : MetaType) : Inner?
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

      def transform_mt_to_span(decided : Array({Key, MetaType}), &block : MetaType -> Span) : Inner
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

      def deciding_exact(key : Key, mt : MetaType) : Inner?
        self
      end

      def deciding_f_cap(f_cap_mt : MetaType, is_constructor : Bool) : Inner?
        self
      end

      def deciding_type_param(type_param : TypeParam, cap : MetaType) : Inner?
        self
      end

      def narrowing_type_param(type_param : TypeParam, cap : MetaType) : Inner?
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
end
