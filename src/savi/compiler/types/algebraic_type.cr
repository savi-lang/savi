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

    def bind_variables(mapping : Hash(TypeVariable, AlgebraicType)) : {AlgebraicType, Bool}
      raise NotImplementedError.new("bind_variables for #{self.class}")
    end

    def trace_as_constraint(cursor : Cursor)
      raise NotImplementedError.new("trace_as_constraint for #{self.class}: #{show}")
    end

    def trace_as_assignment(cursor : Cursor)
      raise NotImplementedError.new("trace_as_assignment for #{self.class}: #{show}")
    end

    def trace_call_return_as_assignment(cursor : Cursor, call : AST::Call)
      raise NotImplementedError.new("trace_call_return_as_assignment for #{self.class}: #{show}")
    end

    def is_assignment_based_on_input_var? : Bool
      raise NotImplementedError.new("trace_call_return_as_assignment for #{self.class}: #{show}")
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

    def intersect(other : AlgebraicType)
      case other
      when NominalCap
        IntersectionBasic.new(self, other)
      when AlgebraicTypeFactor
        Intersection.new(Set(AlgebraicTypeFactor){self, other})
      else
        other.intersect(self)
      end
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

    def bind_variables(mapping : Hash(TypeVariable, AlgebraicType)) : {AlgebraicType, Bool}
      {self, false} # This is not a variable, so there is no effect.
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

    ISO   = new(Cap::ISO)
    VAL   = new(Cap::VAL)
    REF   = new(Cap::REF)
    BOX   = new(Cap::BOX)
    REF_P = new(Cap::REF_P)
    BOX_P = new(Cap::BOX_P)
    TAG   = new(Cap::TAG)
    NON   = new(Cap::NON)

    def self.from_string(string : String) : NominalCap
      case string
      when "iso"  then ISO
      when "val"  then VAL
      when "ref"  then REF
      when "box"  then BOX
      when "ref'" then REF_P
      when "box'" then BOX_P
      when "tag"  then TAG
      when "non"  then NON
      else
        raise NotImplementedError.new("#{self}.from_string(#{string.inspect})")
      end
    end

    def show
      case self
      when ISO   then "iso"
      when VAL   then "val"
      when REF   then "ref"
      when BOX   then "box"
      when REF_P then "ref'"
      when BOX_P then "box'"
      when TAG   then "tag"
      when NON   then "non"
      else
        raise NotImplementedError.new(@cap)
      end
    end

    def intersect(other : AlgebraicType)
      case other
      when NominalType
        IntersectionBasic.new(other, self)
      when AlgebraicTypeFactor
        Intersection.new(Set(AlgebraicTypeFactor){other, self})
      else
        other.intersect(self)
      end
    end

    def aliased
      case self
      when ISO then REF_P
      when REF_P, BOX_P then raise "unreachable: we should never alias an alias"
      else self # all other caps alias as themselves
      end
    end

    def stabilized
      case self
      when REF_P, BOX_P then TAG # TODO: NON instead, for Verona compatibility
      else self # all other caps stabilize as themselves
      end
    end

    def override_cap(other : AlgebraicType)
      other
    end

    def viewed_from(origin)
      if origin.is_a?(NominalCap)
        NominalCap.new(Cap::Logic.viewpoint(origin.cap, cap))
      else
        Viewpoint.new(origin, self)
      end
    end

    def bind_variables(mapping : Hash(TypeVariable, AlgebraicType)) : {AlgebraicType, Bool}
      {self, false} # This is not a variable, so there is no effect.
    end

    def trace_as_constraint(cursor : Cursor)
      # TODO: Is there a source position we can use here?
      # TODO: Should we use the "narrow" bound when generic?
      cursor.add_fact(Source::Pos.none, self)
    end

    def trace_as_assignment(cursor : Cursor)
      # TODO: Is there a source position we can use here?
      # TODO: Should we use the "wider" bound when generic?
      cursor.add_fact(Source::Pos.none, self)
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

    def bind_variables(mapping : Hash(TypeVariable, AlgebraicType)) : {AlgebraicType, Bool}
      binding = mapping[@var]?
      binding ? {binding, true} : {self, false}
    end

    def trace_as_constraint(cursor : Cursor)
      var.trace_as_constraint(cursor)
    end

    def trace_as_assignment(cursor : Cursor)
      var.trace_as_assignment(cursor)
    end

    def trace_call_return_as_assignment(cursor : Cursor, call : AST::Call)
      cursor.trace_var_upper_bound_call_return_as_assignment(call.pos, call, var)
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
    getter field : StructRef(AlgebraicTypeFactor)
    def initialize(origin, field)
      if origin.is_a?(Intersection)
        origin = Intersection.from(
          origin.members.reject(&.is_a?(NominalType))
        )
      elsif origin.is_a?(IntersectionBasic)
        origin = origin.nominal_cap
      end

      @origin = StructRef(AlgebraicTypeSimple).new(origin.as(AlgebraicTypeSimple))
      @field = StructRef(AlgebraicTypeFactor).new(field)
    end

    def show
      "#{@origin.show}->#{@field.show}"
    end

    def bind_variables(mapping : Hash(TypeVariable, AlgebraicType)) : {AlgebraicType, Bool}
      new_origin, origin_changed = origin.value.bind_variables(mapping)
      new_field, field_changed = field.value.bind_variables(mapping)

      return {self, false} unless origin_changed || field_changed

      {new_field.viewed_from(new_origin), true}
    end

    def trace_as_assignment(cursor : Cursor)
      cursor.trace_as_assignment_with_two_step_transform(
        @origin.value,
        @field.value,
      ) { |origin_facts_union, field_fact|
        field_fact.viewed_from(origin_facts_union)
      }
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      # The origin and field types of the viewpoint subtype (right side)
      # must each observe a constraint based on the supertype (left side)
      # and the other term in the three-term relationship.
      @field.value.observe_assignment_reciprocals(
        pos,
        ViewableAs.new(supertype, origin: @origin.value),
        maybe: maybe,
      )
      @origin.value.observe_assignment_reciprocals(
        pos,
        OriginOfViewpoint.new(@field.value, adapted: supertype),
        maybe: maybe,
      )
    end
  end

  struct ViewableAs < AlgebraicTypeSimple
    getter adapted : StructRef(AlgebraicTypeFactor)
    getter origin : StructRef(AlgebraicTypeSimple)
    def initialize(adapted, origin)
      if origin.is_a?(Intersection)
        origin = Intersection.from(
          origin.members.reject(&.is_a?(NominalType))
        )
      elsif origin.is_a?(IntersectionBasic)
        origin = origin.nominal_cap
      end

      @adapted = StructRef(AlgebraicTypeFactor).new(adapted)
      @origin = StructRef(AlgebraicTypeSimple).new(origin.as(AlgebraicTypeSimple))
    end

    def show
      "(viewable_as #{@adapted.show} via #{@origin.show})"
    end
  end

  struct OriginOfViewpoint < AlgebraicTypeSimple
    getter field : StructRef(AlgebraicTypeFactor)
    getter adapted : StructRef(AlgebraicTypeFactor)
    def initialize(field, adapted)
      @field = StructRef(AlgebraicTypeFactor).new(field)
      @adapted = StructRef(AlgebraicTypeFactor).new(adapted)
    end

    def show
      "(origin_of_viewpoint #{@field.show} into #{@adapted.show})"
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

    def bind_variables(mapping : Hash(TypeVariable, AlgebraicType)) : {AlgebraicType, Bool}
      new_inner, is_changed = inner.bind_variables(mapping)
      if is_changed
        return {new_inner.aliased, true}
      else
        return {self, false}
      end
    end

    def trace_as_assignment(cursor : Cursor)
      cursor.trace_as_assignment_with_transform(inner, &.aliased)
    end

    def trace_call_return_as_assignment(cursor : Cursor, call : AST::Call)
      cursor.trace_call_return_as_assignment_with_transform(call, inner, &.aliased)
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

  # IntersectionBasic is a special case optimization of Intersection for the
  # very common case of intersecting a NominalType with a NominalCap.
  # We are able to represent them without an extra Set allocation,
  # and several operations are made more direct and efficient.
  # We also show the type to the user in a streamlined way, using the
  # standard `Type'cap` designation (or `Type` when it matches the default cap).
  struct IntersectionBasic < AlgebraicTypeSummand
    getter nominal_type : NominalType
    getter nominal_cap : NominalCap
    def initialize(@nominal_type, @nominal_cap)
    end

    def show
      "#{@nominal_type.show}'#{@nominal_cap.show}"
    end

    def intersect(other : AlgebraicType)
      case other
      when AlgebraicTypeFactor
        return self if other == @nominal_type || other == @nominal_cap

        Intersection.new(Set(AlgebraicTypeFactor){
          @nominal_type.as(AlgebraicTypeFactor),
          other,
          @nominal_cap.as(AlgebraicTypeFactor),
        })
      when IntersectionBasic
        return self if other == self

        Intersection.new(Set(AlgebraicTypeFactor){
          @nominal_type.as(AlgebraicTypeFactor),
          other.nominal_type.as(AlgebraicTypeFactor),
          @nominal_cap.as(AlgebraicTypeFactor),
          other.nominal_cap.as(AlgebraicTypeFactor),
        })
      when Intersection
        Intersection.new(
          other.members.dup
            .tap(&.add(@nominal_type))
            .tap(&.add(@nominal_cap))
        )
      else
        other.intersect(self)
      end
    end

    def aliased
      # Only the NominalCap is affected.
      IntersectionBasic.new(@nominal_type, @nominal_cap.aliased)
    end

    def stabilized
      # Only the NominalCap is affected.
      IntersectionBasic.new(@nominal_type, @nominal_cap.stabilized)
    end

    def override_cap(cap : AlgebraicType)
      # The NominalCap is replaced.
      if cap.is_a?(NominalCap)
        IntersectionBasic.new(@nominal_type, cap)
      else
        @nominal_type.intersect(cap)
      end
    end

    def viewed_from(origin)
      # Only the NominalCap is affected and the result may not be basic anymore.
      @nominal_type.intersect(@nominal_cap.viewed_from(origin))
    end

    def bind_variables(mapping : Hash(TypeVariable, AlgebraicType)) : {AlgebraicType, Bool}
      # Neither NominalCap nor NominalType are variables, so there is no effect.
      {self, false}
    end

    def trace_as_constraint(cursor : Cursor)
      cursor.add_fact_at_current_pos(self)
    end

    def trace_as_assignment(cursor : Cursor)
      cursor.add_fact_at_current_pos(self)
    end

    def trace_call_return_as_assignment(cursor : Cursor, call : AST::Call)
      cursor.trace_nominal_call_return_as_assignment(call, @nominal_type, @nominal_cap)
    end

    def observe_assignment_reciprocals(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe : Bool = false,
    )
      # Neither NominalType nor NominalCap cares about receiving inference hints
      # because their type is not variable and thus not in need of inference.
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
      case @members.size
      when 0 then raise NotImplementedError.new("algebraic top type")
      when 1 then @members.first.show
      else "(#{@members.map(&.show).join(" & ")})"
      end
    end

    def intersect(other : AlgebraicType)
      case other
      when AlgebraicTypeFactor
        Intersection.new(@members.dup.tap(&.add(other)))
      when IntersectionBasic
        Intersection.new(
          @members.dup
            .tap(&.add(other.nominal_type))
            .tap(&.add(other.nominal_cap))
        )
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

    def bind_variables(mapping : Hash(TypeVariable, AlgebraicType)) : {AlgebraicType, Bool}
      any_is_changed = false
      new_members = @members.map { |member|
        new_member, is_changed = member.bind_variables(mapping)
        any_is_changed ||= is_changed
        new_member.as(AlgebraicType)
      }
      {
        any_is_changed ? Intersection.from(new_members) : self,
        any_is_changed
      }
    end

    def trace_as_assignment(cursor : Cursor)
      raise NotImplementedError.new("trace_as_assignment for #{self.class}: #{show}") \
        unless @members.size == 2 \
          && @members.any?(&.is_a?(NominalType)) \
          && @members.any?(&.is_a?(NominalCap))

      cursor.add_fact_at_current_pos(self)
    end

    def trace_call_return_as_assignment(cursor : Cursor, call : AST::Call)
      raise NotImplementedError.new("trace_as_assignment for #{self.class}: #{show}") \
        unless @members.size == 2 \
          && (nominal_type = @members.find(&.as?(NominalType))) \
          && (nominal_cap = @members.find(&.as?(NominalCap)))

      cursor.trace_nominal_call_return_as_assignment(
        call, nominal_type.as(NominalType), nominal_cap.as(NominalCap)
      )
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
      case @members.size
      when 0 then raise NotImplementedError.new("algebraic bottom type")
      when 1 then @members.first.show
      else "(#{@members.map(&.show).join(" | ")})"
      end
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
