module Savi::Compiler::Infer
  struct Conduit
    getter inner : Inner
    def initialize(@inner)
    end

    def flatten : Array(Conduit)
      inner.flatten.map { |flat_inner| Conduit.new(flat_inner) }
    end

    def directly_references?(other_info : Info) : Bool
      inner.directly_references?(other_info)
    end

    def resolve_span!(ctx : Context, infer : Visitor) : Span
      inner.resolve_span!(ctx, infer)
    end
    def resolve_span!(infer : Analysis) : Span
      inner.resolve_span!(infer)
    end
    def resolve!(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : MetaType?
      inner.resolve!(ctx, type_check)
    end

    abstract struct Inner
      abstract def flatten : Array(Inner)
      abstract def directly_references?(other_info : Info) : Bool
      abstract def resolve_span!(ctx : Context, infer : Visitor) : Span
      abstract def resolve!(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : MetaType?
    end

    def self.direct(info)
      new(Direct.new(info))
    end

    struct Direct < Inner
      getter info : Info
      def initialize(@info)
      end

      def pretty_print(format : PrettyPrint)
        format.surround("Direct(", ")", left_break: nil, right_break: nil) do
          format.text(info.to_s)
        end
      end

      def flatten : Array(Inner)
        conduit = info.as_conduit?
        conduit ? conduit.inner.flatten : [self] of Inner
      end

      def directly_references?(other_info : Info) : Bool
        @info == other_info
      end

      def resolve_span!(ctx : Context, infer : Visitor) : Span
        infer.resolve(ctx, info)
      end
      def resolve_span!(infer : Analysis) : Span
        infer[info]
      end
      def resolve!(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : MetaType?
        type_check.resolve(ctx, info)
      end
    end

    def self.union(infos)
      new(Union.new(infos))
    end

    struct Union < Inner
      getter infos : Array(Info)
      def initialize(@infos)
      end

      def pretty_print(format : PrettyPrint)
        format.surround("Union([", " ])", left_break: " ", right_break: nil) do
          infos.each_with_index do |info, index|
            format.breakable ", " if index != 0
            format.text(info.to_s)
          end
        end
      end

      def flatten : Array(Inner)
        infos.flat_map do |info|
          conduit = info.as_conduit?
          conduit ? conduit.inner.flatten : [Direct.new(info)] of Inner
        end
      end

      def directly_references?(other_info : Info) : Bool
        @infos.includes?(other_info)
      end

      def resolve_span!(ctx : Context, infer : Visitor) : Span
        return Span.simple(MetaType.unsatisfiable) if @infos.empty?

        spans = @infos.map { |info| infer.resolve(ctx, info) }
        Span
          .reduce_combine_mts(spans) { |accum, mt| accum.unite(mt) }
          .not_nil!
      end

      def resolve_span!(infer : Analysis) : Span
        return Span.simple(MetaType.unsatisfiable) if @infos.empty?

        spans = @infos.map { |info| infer[info].as(Span) }
        Span
          .reduce_combine_mts(spans) { |accum, mt| accum.unite(mt) }
          .not_nil!
      end

      def resolve!(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : MetaType?
        mts = @infos.compact_map { |info| type_check.resolve(ctx, info).as(MetaType?) }
        return nil if mts.empty?
        MetaType.new_union(mts)
      end
    end

    def self.consumed(info)
      new(Consumed.new(info))
    end

    struct Consumed < Inner
      getter info : Info
      def initialize(@info)
      end

      def pretty_print(format : PrettyPrint)
        format.surround("Consumed(", ")", left_break: nil, right_break: nil) do
          format.text(info.to_s)
        end
      end

      def flatten : Array(Inner)
        conduit = info.as_conduit?
        return [self] of Inner unless conduit

        conduit.flatten.map do |flat_conduit|
          flat_inner = flat_conduit.inner
          case flat_inner
          when Direct; Consumed.new(flat_inner.info)
          when Consumed; Consumed.new(flat_inner.info)
          when Aliased; Direct.new(flat_inner.info)
          else raise NotImplementedError.new(flat_inner.inspect)
          end.as(Inner)
        end
      end

      def directly_references?(other_info : Info) : Bool
        @info == other_info
      end

      def resolve_span!(ctx : Context, infer : Visitor) : Span
        infer.resolve(ctx, info).transform_mt(&.consumed)
      end
      def resolve_span!(infer : Analysis) : Span
        infer[info].transform_mt(&.consumed)
      end
      def resolve!(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : MetaType?
        type_check.resolve(ctx, info).try(&.consumed)
      end
    end

    def self.aliased(info)
      new(Aliased.new(info))
    end

    struct Aliased < Inner
      getter info : Info
      def initialize(@info)
      end

      def pretty_print(format : PrettyPrint)
        format.surround("Aliased(", ")", left_break: nil, right_break: nil) do
          format.text(info.to_s)
        end
      end

      def flatten : Array(Inner)
        conduit = info.as_conduit?
        return [self] of Inner unless conduit

        conduit.flatten.map do |flat_conduit|
          flat_inner = flat_conduit.inner
          case flat_inner
          when Direct; Aliased.new(flat_inner.info)
          when Consumed; Direct.new(flat_inner.info)
          when Aliased; Aliased.new(flat_inner.info)
          else raise NotImplementedError.new(flat_inner.inspect)
          end
        end
      end

      def directly_references?(other_info : Info) : Bool
        @info == other_info
      end

      def resolve_span!(ctx : Context, infer : Visitor) : Span
        infer.resolve(ctx, info).transform_mt(&.aliased)
      end
      def resolve_span!(infer : Analysis) : Span
        infer[info].transform_mt(&.aliased)
      end
      def resolve!(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : MetaType?
        type_check.resolve(ctx, info).try(&.aliased)
      end
    end

    def self.array_literal_element_antecedent(array_info)
      new(ArrayLiteralElementAntecedent.new(array_info))
    end

    struct ArrayLiteralElementAntecedent < Inner
      getter array_info : Info
      def initialize(@array_info)
      end

      def pretty_print(format : PrettyPrint)
        name = "ArrayLiteralElementAntecedent"
        format.surround("#{name}(", ")", left_break: nil, right_break: nil) do
          format.text(array_info.to_s)
        end
      end

      def flatten : Array(Inner)
        conduit = array_info.as_conduit?
        return [self] of Inner unless conduit

        conduit.flatten.map(&.inner)
      end

      def directly_references?(other_info : Info) : Bool
        @array_info == other_info
      end

      def resolve_span!(ctx : Context, infer : Visitor) : Span
        infer.resolve(ctx, array_info).transform_mt(&.single!.args.first)
      end
      def resolve_span!(infer : Analysis) : Span
        infer[array_info].transform_mt(&.single!.args.first)
      end
      def resolve!(ctx : Context, type_check : TypeCheck::ForReifiedFunc) : MetaType?
        type_check.resolve(ctx, array_info)
          .try(&.single!.args.first)

          # We may need to unwrap type aliases.
          .try(&.substitute_each_type_alias_in_first_layer { |rta|
            rta.meta_type_of_target(ctx).not_nil!
          })
      end
    end
  end
end