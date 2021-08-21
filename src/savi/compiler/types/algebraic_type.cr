module Savi::Compiler::Types
  abstract struct AlgebraicType
    def inspect; show; end
    abstract def show

    abstract def intersect(other : AlgebraicType)

    def aliased
      raise NotImplementedError.new("aliased for #{self.class}")
    end

    def stabilized
      raise NotImplementedError.new("stabilized for #{self.class}")
    end

    def override_cap(cap : AlgebraicType)
      raise NotImplementedError.new("override_cap for #{self.class}")
    end

    def viewed_from(origin)
      raise NotImplementedError.new("viewed_from for #{self.class}")
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      raise NotImplementedError.new("observe_assignment_reciprocals for #{self.class}: #{show}")
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

  abstract struct AlgebraicTypeFactor < AlgebraicTypeSummand
    def intersect(other : AlgebraicType)
      case other
      when AlgebraicTypeFactor
        Intersection.new(Set(AlgebraicTypeFactor){self, other})
      else
        other.intersect(self)
      end
    end

    def viewed_from(origin)
      Viewpoint.new(origin, self)
    end
  end

  abstract struct AlgebraicTypeSimple < AlgebraicTypeFactor
    def aliased
      Aliased.new(self)
    end

    def stabilized
      Stabilized.new(self)
    end
  end

  struct JumpsAway < AlgebraicType
    getter pos : Source::Pos
    def initialize(@pos)
    end

    def show
      "(jumps away)"
    end

    def intersect(other : AlgebraicType)
      # No matter what you intersect, the type is still just not there.
      # It has jumped away without leaving anything to intersect with.
      self
    end

    def unite(other : AlgebraicType)
      # Whatever the other type is, we use it and abandon this lack of a type.
      other
    end

    def aliased
      self # doesn't change the nature of this lack of a type
    end

    def stabilized
      self # doesn't change the nature of this lack of a type
    end

    def override_cap(cap : AlgebraicType)
      self # doesn't change the nature of this lack of a type
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      # Do nothing.
      # Only a type variable can be modified by observations about it.
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

    def aliased
      self # this type says nothing about capabilities, so it remains unchanged.
    end

    def stabilized
      self # this type says nothing about capabilities, so it remains unchanged.
    end

    def override_cap(cap : AlgebraicType)
      intersect(cap)
    end

    def viewed_from(origin)
      self # this type says nothing about capabilities, so it remains unchanged.
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      # Do nothing - the nominal type is fixed by other factors.
      # Only a type variable can be modified by observations about it.
    end
  end

  struct NominalCap < AlgebraicTypeSimple
    getter cap : Cap::Value
    def initialize(@cap)
    end

    ISO         = new(Cap::ISO)
    ISO_ALIASED = new(Cap::ISO_ALIASED)
    REF         = new(Cap::REF)
    VAL         = new(Cap::VAL)
    BOX         = new(Cap::BOX)
    TAG         = new(Cap::TAG)
    NON         = new(Cap::NON)

    ANY   = new(Cap::ISO | Cap::REF | Cap::VAL | Cap::BOX | Cap::TAG | Cap::NON)
    ALIAS = new(Cap::REF | Cap::VAL | Cap::BOX | Cap::TAG | Cap::NON)
    SEND  = new(Cap::ISO | Cap::VAL | Cap::TAG | Cap::NON)
    SHARE = new(Cap::VAL | Cap::TAG | Cap::NON)
    READ  = new(Cap::REF | Cap::VAL | Cap::BOX)

    def show
      case self
      when ISO         then "iso"
      when ISO_ALIASED then "iso'aliased"
      when REF         then "ref"
      when VAL         then "val"
      when BOX         then "box"
      when TAG         then "tag"
      when NON         then "non"
      when ANY         then "any"
      when ALIAS       then "alias"
      when SEND        then "send"
      when SHARE       then "share"
      when READ        then "read"
      else
        String.build { |str|
          str << "{"
          Cap::Logic::BITS.each { |name, bits|
            next unless (@cap & bits) != 0
            str << "|" unless str.empty?
            str << name
          }
          str << "}"
        }
      end
    end

    def aliased
      case self
      when ISO then ISO_ALIASED
      when ISO_ALIASED then raise "unreachable: we should never alias an alias"
      else self # all other caps alias as themselves
      end
    end

    def stabilized
      case self
      when ISO_ALIASED then TAG # TODO: NON instead, for Verona compatibility
      else self # all other caps stabilize as themselves
      end
    end

    def override_cap(other : AlgebraicType)
      other
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      # Do nothing - the nominal cap is fixed by other factors.
      # Only a type variable can be modified by observations about it.
    end
  end

  struct TypeVariableRef < AlgebraicTypeSimple
    getter var : TypeVariable
    def initialize(@var)
    end

    def show
      @var.show_name
    end

    def override_cap(cap : AlgebraicType)
      if @var.is_cap_var
        cap # overrides whatever cap was sitting behind this variable
      else
        OverrideCap.new(self, cap)
      end
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      # The reciprocal of an assignment (the subtype acting on supertype)
      # is a constraint (the supertype acting on the subtype).
      var.observe_constraint_at(
        pos, supertype, maybe: maybe, via_reciprocal: true
      )
    end
  end

  struct Viewpoint < AlgebraicTypeSimple
    getter origin : StructRef(AlgebraicTypeSimple)
    getter target : StructRef(AlgebraicTypeFactor)
    def initialize(origin, target)
      if origin.is_a?(Intersection)
        origin = Intersection.from(
          origin.members.reject(&.is_a?(NominalType))
        )
      end

      @origin = StructRef(AlgebraicTypeSimple).new(origin.as(AlgebraicTypeSimple))
      @target = StructRef(AlgebraicTypeFactor).new(target)
    end

    def show
      "#{@origin.show}->#{@target.show}"
    end
  end

  struct OverrideCap < AlgebraicTypeFactor
    getter inner : AlgebraicTypeSimple
    getter cap : StructRef(AlgebraicType)
    def initialize(@inner, cap : AlgebraicType)
      @cap = StructRef(AlgebraicType).new(cap)
    end

    def show
      "#{@inner.show}'#{@cap.show}"
    end
  end

  struct Aliased < AlgebraicTypeFactor
    getter inner : AlgebraicTypeSimple
    def initialize(@inner)
    end

    def show
      "#{@inner.show}'aliased"
    end

    def aliased
      raise "unreachable: we should never alias an alias"
    end

    def stabilized
      # If we stabilize an alias, only those caps with no uniqueness constraints
      # can remain in play - if an iso'aliased is present, it drops away.
      NoUnique.new(inner)
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      # TODO: Should we do something other than discard the alias layer here?
      inner.observe_assignment_reciprocals(pos, supertype, maybe)
    end
  end

  struct Stabilized < AlgebraicTypeFactor
    getter inner : AlgebraicTypeSimple
    def initialize(@inner)
    end

    def show
      "#{@inner.show}'stabilized"
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      # Assigning from stabilized subtype (right side) implies that the
      # supertype (left side) must also be in the domain of stable capabilities.
      inner.observe_assignment_reciprocals(pos, supertype.stabilized, maybe)
    end
  end

  struct NoUnique < AlgebraicTypeFactor
    getter inner : AlgebraicTypeSimple
    def initialize(@inner)
    end

    def show
      "#{@inner.show}'nounique"
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      # TODO: Should we do something other than discard the alias layer here?
      inner.observe_assignment_reciprocals(pos, supertype, maybe)
    end
  end

  struct Intersection < AlgebraicTypeSummand
    getter members : Set(AlgebraicTypeFactor)
    def initialize(@members)
    end

    def self.from(list)
      result : AlgebraicType? = nil
      list.each { |member|
        result = result ? result.intersect(member) : member
      }
      result.not_nil!
    end

    def show
      "(#{@members.map(&.show).join(" & ")})"
    end

    def intersect(other : AlgebraicType)
      case other
      when AlgebraicTypeFactor
        Intersection.new(@members.dup.tap(&.add(other)))
      when Intersection
        Intersection.new(@members + other.members)
      else
        other.intersect(self)
      end
    end

    def aliased
      Intersection.from(@members.map(&.aliased))
    end

    def stabilized
      Intersection.from(@members.map(&.stabilized))
    end

    def override_cap(cap : AlgebraicType)
      Intersection.from(@members.map(&.override_cap(cap)))
    end

    def viewed_from(origin)
      Intersection.from(@members.map(&.viewed_from(origin)))
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      # Each member of the intersection subtype (right side) MAY observe the
      # constraints of the supertype (left side) as a suggestion.
      @members.each(&.observe_assignment_reciprocals(pos, supertype, maybe: true))
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
      Union.from(@members.map(&.intersect(other)))
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

    def aliased
      Union.from(@members.map(&.aliased))
    end

    def stabilized
      Union.from(@members.map(&.stabilized))
    end

    def override_cap(cap : AlgebraicType)
      Union.from(@members.map(&.override_cap(cap)))
    end

    def viewed_from(origin)
      Union.from(@members.map(&.viewed_from(origin)))
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      # Every member of the union subtype (right side) must observe the
      # constraints of the supertype (left side) it is being assigned to.
      @members.each(&.observe_assignment_reciprocals(pos, supertype, maybe))
    end
  end
end
