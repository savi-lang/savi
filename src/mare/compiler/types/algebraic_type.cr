module Mare::Compiler::Types
  abstract struct AlgebraicType
    def inspect; show; end
    abstract def show

    abstract def intersect(other : AlgebraicType)

    def aliased
      # TODO: Implement this method.
      self
    end

    def stabilized
      # TODO: Implement this method.
      self
    end
  end

  abstract struct AlgebraicTypeSummand < AlgebraicType
    def unite(other : AlgebraicType)
      case other
      when AlgebraicTypeSummand
        Union.new(Set(AlgebraicTypeSummand){self, other})
      else
        other.unite(self)
      end
    end
  end

  abstract struct AlgebraicTypeSimple < AlgebraicTypeSummand
    def intersect(other : AlgebraicType)
      case other
      when AlgebraicTypeSimple
        Intersection.new(Set(AlgebraicTypeSimple){self, other})
      else
        other.intersect(self)
      end
    end
  end

  struct NominalType < AlgebraicTypeSimple
    getter link : Program::Type::Link
    getter args : Array(AlgebraicType)?
    def initialize(@link, @args = nil)
    end

    def show
      args = @args
      args ? "#{@link.name}(#{args.map(&.show).join(", ")})" : @link.name
    end
  end

  struct NominalCap < AlgebraicTypeSimple
    getter cap : String # TODO: probably an enum
    def initialize(@cap)
    end

    def show
      @cap
    end
  end

  struct TypeVariable < AlgebraicTypeSimple
    getter nickname : String
    getter scope : Program::Function::Link | Program::Type::Link | Program::TypeAlias::Link
    getter sequence_number : UInt64
    def initialize(@nickname, @scope, @sequence_number)
    end

    def show
      scope_sym = scope.is_a?(Program::Function::Link) ? "'" : "'^"
      "T'#{@nickname}#{scope_sym}#{@sequence_number}"
    end
  end

  struct CapVariable < AlgebraicTypeSimple
    getter nickname : String
    getter scope : Program::Function::Link | Program::Type::Link | Program::TypeAlias::Link
    getter sequence_number : UInt64
    def initialize(@nickname, @scope, @sequence_number)
    end

    def show
      scope_sym = scope.is_a?(Program::Function::Link) ? "'" : "'^"
      "K'#{@nickname}#{scope_sym}#{@sequence_number}"
    end
  end

  struct Intersection < AlgebraicTypeSummand
    getter members : Set(AlgebraicTypeSimple)
    def initialize(@members)
    end

    def show
      "(#{@members.map(&.show).join(" & ")})"
    end

    def intersect(other : AlgebraicType)
      case other
      when AlgebraicTypeSimple
        Intersection.new(@members.dup.tap(&.add(other)))
      when Intersection
        Intersection.new(@members + other.members)
      else
        other.intersect(self)
      end
    end
  end

  struct Union < AlgebraicType
    getter members : Set(AlgebraicTypeSummand)
    def initialize(@members)
    end

    def self.from(list)
      result : AlgebraicType? = nil
      list.each { |member|
        result = result ? result.unite(member) : member
      }
      result.not_nil!
    end

    def show
      "(#{@members.map(&.show).join(" | ")})"
    end

    def intersect(other : AlgebraicType)
      raise NotImplementedError.new("Union.intersect")
    end

    def unite(other : AlgebraicType)
      case other
      when AlgebraicTypeSummand
        Union.new(@members.dup.tap(&.add(other)))
      when Union
        Union.new(@members + other.members)
      else
        other.unite(self)
      end
    end
  end
end
