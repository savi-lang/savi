module Mare::Compiler::AltInfer
  struct Conduit
    getter inner : Inner
    def initialize(@inner)
    end

    def flatten : Array(Conduit)
      inner.flatten.map { |flat_inner| Conduit.new(flat_inner) }
    end

    def directly_references?(other_info : Infer::Info) : Bool
      inner.directly_references?(other_info)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      inner.resolve_span!(ctx, infer)
    end
    def resolve!(ctx : Context, infer : TypeCheck::ForReifiedFunc) : Infer::MetaType
      inner.resolve!(ctx, infer)
    end

    abstract struct Inner
      abstract def flatten : Array(Inner)
      abstract def directly_references?(other_info : Infer::Info) : Bool
      abstract def resolve_span!(ctx : Context, infer : Visitor) : Span
      abstract def resolve!(ctx : Context, infer : TypeCheck::ForReifiedFunc) : Infer::MetaType
    end

    def self.direct(info)
      new(Direct.new(info))
    end

    struct Direct < Inner
      getter info : Infer::Info
      def initialize(@info)
      end

      def flatten : Array(Inner)
        [self] of Inner
      end

      def directly_references?(other_info : Infer::Info) : Bool
        @info == other_info
      end

      def resolve_span!(ctx : Context, infer : Visitor) : Span
        infer.resolve(ctx, info)
      end
      def resolve!(ctx : Context, infer : TypeCheck::ForReifiedFunc) : Infer::MetaType
        infer.resolve(ctx, info)
      end
    end

    def self.union(infos)
      new(Union.new(infos))
    end

    struct Union < Inner
      getter infos : Array(Infer::Info)
      def initialize(@infos)
        raise ArgumentError.new("empty union") if @infos.empty?
      end

      def flatten : Array(Inner)
        infos.flat_map do |info|
          conduit = info.as_conduit?
          conduit ? conduit.inner.flatten : [Direct.new(info)] of Inner
        end
      end

      def directly_references?(other_info : Infer::Info) : Bool
        @infos.includes?(other_info)
      end

      def resolve_span!(ctx : Context, infer : Visitor) : Span
        spans = @infos.map { |info| infer.resolve(ctx, info) }
        Span
          .combine_mts(spans) { |mts| Infer::MetaType.new_union(mts) }
          .not_nil!
      end
      def resolve!(ctx : Context, infer : TypeCheck::ForReifiedFunc) : Infer::MetaType
        mts = @infos.map { |info| infer.resolve(ctx, info) }
        Infer::MetaType.new_union(mts)
      end
    end

    def self.ephemeralize(info)
      new(Ephemeralize.new(info))
    end

    struct Ephemeralize < Inner
      getter info : Infer::Info
      def initialize(@info)
      end

      def flatten : Array(Inner)
        conduit = info.as_conduit?
        return [self] of Inner unless conduit

        conduit.flatten.map do |flat_conduit|
          flat_inner = flat_conduit.inner
          case flat_inner
          when Direct; Ephemeralize.new(flat_inner.info)
          when Ephemeralize; Ephemeralize.new(flat_inner.info)
          when Alias; Direct.new(flat_inner.info)
          else raise NotImplementedError.new(flat_inner.inspect)
          end
        end
      end

      def directly_references?(other_info : Infer::Info) : Bool
        @info == other_info
      end

      def resolve_span!(ctx : Context, infer : Visitor) : Span
        infer.resolve(ctx, info).transform_mt(&.ephemeralize)
      end
      def resolve!(ctx : Context, infer : TypeCheck::ForReifiedFunc) : Infer::MetaType
        infer.resolve(ctx, info).ephemeralize
      end
    end

    def self.alias(info)
      new(Alias.new(info))
    end

    struct Alias < Inner
      getter info : Infer::Info
      def initialize(@info)
      end

      def flatten : Array(Inner)
        conduit = info.as_conduit?
        return [self] of Inner unless conduit

        conduit.flatten.map do |flat_conduit|
          flat_inner = flat_conduit.inner
          case flat_inner
          when Direct; Alias.new(flat_inner.info)
          when Ephemeralize; Direct.new(flat_inner.info)
          when Alias; Alias.new(flat_inner.info)
          else raise NotImplementedError.new(flat_inner.inspect)
          end
        end
      end

      def directly_references?(other_info : Infer::Info) : Bool
        @info == other_info
      end

      def resolve_span!(ctx : Context, infer : Visitor) : Span
        infer.resolve(ctx, info).transform_mt(&.alias)
      end
      def resolve!(ctx : Context, infer : TypeCheck::ForReifiedFunc) : Infer::MetaType
        infer.resolve(ctx, info).alias
      end
    end
  end
end