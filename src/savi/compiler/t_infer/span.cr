module Savi::Compiler::TInfer
  struct Span
    getter inner : Inner
    def initialize(@inner)
    end

    def pretty_print(format : PrettyPrint)
      format.surround("Span(", ")", left_break: nil, right_break: nil) do
        inner.pretty_print(format)
      end
    end

    def self.simple(mt : MetaType); new(Terminal.new(mt)); end

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

    def terminal!
      inner = inner()
      raise NotImplementedError.new(self) unless inner.is_a?(Terminal)
      inner.meta_type
    end

    def any_error?
      inner.any_error?
    end

    def total_error
      inner.total_error
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

    def transform_mt_to_span(&block : MetaType -> Span) : Span
      Span.new(inner.transform_mt_to_span(&block))
    end

    def combine_mt_to_span(other : Span, &block : (MetaType, MetaType) -> Span) : Span
      Span.new(inner.combine_mt_to_span(other.inner, &block))
    end

    def combine_mt(other : Span, &block : (MetaType, MetaType) -> MetaType) : Span
      mt_block = ->(a : MetaType, b : MetaType) {
        Span.simple(block.call(a, b))
      }
      Span.new(inner.combine_mt_to_span(other.inner, &mt_block))
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
      abstract def all_terminal_meta_types : Array(MetaType)
      abstract def any_mt?(&block : MetaType -> Bool) : Bool
      abstract def each_mt(&block : MetaType -> Nil) : Nil
      abstract def transform_mt(&block : MetaType -> MetaType) : Inner
      abstract def transform_mt_to_span(&block : MetaType -> Span) : Inner
      abstract def combine_mt_to_span(other : Inner, &block : (MetaType, MetaType) -> Span) : Inner
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

      def transform_mt_to_span(&block : MetaType -> Span) : Inner
        block.call(@meta_type).inner
      end

      def combine_mt_to_span(other : Inner, &block : (MetaType, MetaType) -> Span) : Inner
        if other.is_a?(Terminal)
          block.call(self.meta_type, other.meta_type).inner
        else
          swap_block = -> (b : MetaType, a : MetaType) { block.call(a, b) }
          other.combine_mt_to_span(self, &swap_block)
        end
      end

      def maybe_fallback_based_on_mt_simplify(options : Array({Symbol, Inner})) : Inner
        Fallback.build(self, @meta_type, options)
      end

      def final_mt_simplify(ctx : Context) : Inner
        Terminal.new(meta_type.simplify(ctx))
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

      def transform_mt_to_span(&block : MetaType -> Span) : Inner
        Fallback.build(
          @default.value.transform_mt_to_span(&block),
          @evaluate_mt,
          @options.map { |(cond, inner)|
            {cond, inner.transform_mt_to_span(&block)}
          }
        )
      end

      def combine_mt_to_span(other : Inner, &block : (MetaType, MetaType) -> Span) : Inner
        if other.is_a?(Terminal)
          Fallback.build(
            @default.value.combine_mt_to_span(other, &block),
            @evaluate_mt,
            @options.map { |(cond, inner)|
              {cond, inner.combine_mt_to_span(other, &block).as(Inner)}
            }
          )
        elsif !other.is_a?(Fallback)
          swap_block = -> (b : MetaType, a : MetaType) { block.call(a, b) }
          return other.combine_mt_to_span(self, &swap_block)
        elsif other.is_a?(Fallback) && \
          other.evaluate_mt == self.evaluate_mt && \
          other.options.map(&.first) == self.options.map(&.first)

          Fallback.build(
            @default.value.combine_mt_to_span(other.default.value, &block),
            @evaluate_mt,
            @options.map { |(cond, inner)|
              other_inner = other.options.find(&.first.==(cond)).not_nil!.last
              {cond, inner.combine_mt_to_span(other_inner, &block).as(Inner)}
            }
          )
        elsif other.is_a?(Fallback) && other.evaluate_mt != self.evaluate_mt
          Fallback.build(
            @default.value.combine_mt_to_span(other, &block),
            @evaluate_mt,
            @options.map { |(cond, inner)|
              {cond, inner.combine_mt_to_span(other, &block).as(Inner)}
            }
          )
        else
          raise NotImplementedError.new(
            "combine_mt_to_span for two fallbacks with the same " \
            "evaluate_mt but different options"
          )
        end
      end

      def maybe_fallback_based_on_mt_simplify(options : Array({Symbol, Inner})) : Inner
        Fallback.build(
          @default.value.maybe_fallback_based_on_mt_simplify(options),
          @evaluate_mt,
          @options.map { |(cond, inner)| {cond, inner.maybe_fallback_based_on_mt_simplify(options)} }
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

      def transform_mt_to_span(&block : MetaType -> Span) : Inner
        self
      end

      def combine_mt_to_span(other : Inner, &block : (MetaType, MetaType) -> Span) : Inner
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
