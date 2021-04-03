struct Mare::Compiler::Infer::MetaType::AntiNominal
  getter defn : ReifiedType

  def initialize(defn)
    raise NotImplementedError.new(defn) unless defn.is_a?(ReifiedType)
    @defn = defn
  end

  def inspect(io : IO)
    io << "-"
    io << defn.link.name
    io << "'any"
  end

  def each_reachable_defn(ctx : Context) : Array(ReifiedType)
    ([] of ReifiedType)
  end

  def gather_call_receiver_span(
    ctx : Context,
    pos : Source::Pos,
    infer : Visitor?,
    name : String
  ) : Span
    Span.error(pos,
      "The '#{name}' function can't be called on this receiver", [
        {pos, "the type #{self.inspect} has no types defining that function"}
      ]
    )
  end

  def find_callable_func_defns(ctx, name : String)
    nil
  end

  def any_callable_func_defn_type(ctx, name : String) : ReifiedType?
    nil
  end

  def is_concrete?
    defn.link.is_concrete?
  end

  def negate : Inner
    Nominal.new(defn)
  end

  def intersect(other : Unconstrained)
    self
  end

  def intersect(other : Unsatisfiable)
    other
  end

  def intersect(other : Capability)
    Intersection.new(other, nil, [self].to_set)
  end

  def intersect(other : Nominal)
    # Unsatisfiable if the nominal and anti-nominal types are identical.
    return Unsatisfiable.instance if defn == other.defn

    # Otherwise, this is a new intersection of the two types.
    Intersection.new(nil, [other].to_set, [self].to_set)
  end

  def intersect(other : AntiNominal)
    # No change if the two anti-nominal types are identical.
    return self if defn == other.defn

    # Otherwise, this is a new intersection of the two types.
    Intersection.new(nil, nil, [self, other].to_set)
  end

  def intersect(other : (Intersection | Union))
    other.intersect(self) # delegate to the "higher" class via commutativity
  end

  def unite(other : Unconstrained)
    other
  end

  def unite(other : Unsatisfiable)
    self
  end

  def unite(other : Capability)
    Union.new([other].to_set, nil, [self].to_set)
  end

  def unite(other : Nominal)
    # Unconstrained if the nominal and anti-nominal types are identical.
    return Unconstrained.instance if defn == other.defn

    # Otherwise, this is a new union of the two types.
    Union.new(nil, [other].to_set, [self].to_set)
  end

  def unite(other : AntiNominal)
    # No change if the two anti-nominal types are identical.
    return self if defn == other.defn

    # Unconstrained if the two are concrete types that are not identical.
    return Unconstrained.instance if is_concrete? && other.is_concrete?

    # Otherwise, this is a new union of the two types.
    Union.new(nil, nil, [self, other].to_set)
  end

  def unite(other : (Intersection | Union))
    other.unite(self) # delegate to the "higher" class via commutativity
  end

  def ephemeralize
    self # no effect
  end

  def strip_ephemeral
    self # no effect
  end

  def alias
    self # no effect
  end

  def strip_cap
    self # no effect
  end

  def partial_reifications
    # Intersect with every possible non-ephemeral cap.
    Capability::ALL_NON_EPH.map(&.intersect(self)).to_set
  end

  def type_params
    defn = defn()
    if defn.is_a?(TypeParam)
      [defn].to_set
    else
      Set(TypeParam).new
    end
  end

  def substitute_type_params(substitutions : Hash(TypeParam, MetaType))
    defn = defn()
    case defn
    when TypeParam
      substitutions[defn]?.try(&.inner.negate) || self
    when ReifiedType
      args = defn.args.map do |arg|
        arg.substitute_type_params(substitutions).as(MetaType)
      end

      AntiNominal.new(ReifiedType.new(defn.link, args))
    when ReifiedTypeAlias
      args = defn.args.map do |arg|
        arg.substitute_type_params(substitutions).as(MetaType)
      end

      AntiNominal.new(ReifiedTypeAlias.new(defn.link, args))
    else
      raise NotImplementedError.new(defn)
    end
  end

  def substitute_lazy_type_params(substitutions : Hash(TypeParam, MetaType), max_depth : Int)
    defn = defn()
    case defn
    when TypeParam
      return self unless defn.lazy?
      substitutions[defn]?.try(&.inner.negate) || self
    when ReifiedType
      return self unless max_depth > 0

      args = defn.args.map do |arg|
        arg.substitute_lazy_type_params(substitutions, max_depth - 1).as(MetaType)
      end

      AntiNominal.new(ReifiedType.new(defn.link, args))
    when ReifiedTypeAlias
      return self unless max_depth > 0

      args = defn.args.map do |arg|
        arg.substitute_lazy_type_params(substitutions, max_depth - 1).as(MetaType)
      end

      AntiNominal.new(ReifiedTypeAlias.new(defn.link, args))
    else
      raise NotImplementedError.new(defn)
    end
  end

  def gather_lazy_type_params_referenced(ctx : Context, set : Set(TypeParam), max_depth : Int) : Set(TypeParam)
    defn = defn()
    case defn
    when TypeParam
      set.add(defn) if defn.lazy?
    when ReifiedType
      if max_depth > 0
        defn.args.each(&.gather_lazy_type_params_referenced(ctx, set, max_depth - 1))
      end
    when ReifiedTypeAlias
      if max_depth > 0
        defn.args.each(&.gather_lazy_type_params_referenced(ctx, set, max_depth - 1))
      end
    else
      raise NotImplementedError.new(defn)
    end
    set
  end

  def each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> _)
    raise NotImplementedError.new("#{self} each_type_alias_in_first_layer")
  end

  def substitute_each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> MetaType) : Inner
    raise NotImplementedError.new("#{self} substitute_each_type_alias_in_first_layer")
  end

  def is_sendable?
    # An anti-nominal is never itself sendable -
    # it excludes a single nominal, and says nothing about capabilities.
    false
  end

  def safe_to_match_as?(ctx : Context, other) : Bool?
    raise NotImplementedError.new("#{self.inspect} safe_to_match_as?")
  end

  def recovered
    raise NotImplementedError.new("#{self.inspect} recovered")
  end

  def viewed_from(origin)
    raise NotImplementedError.new("#{origin.inspect}->#{self.inspect}")
  end

  def extracted_from(origin)
    raise NotImplementedError.new("#{origin.inspect}->>#{self.inspect}")
  end

  def subtype_of?(ctx : Context, other : Capability) : Bool
    # An anti-nominal can never be a subtype of any capability -
    # it excludes a single nominal, and says nothing about capabilities.
    false
  end

  def supertype_of?(ctx : Context, other : Capability) : Bool
    # An anti-nominal can never be a supertype of any capability -
    # it excludes a single nominal, and says nothing about capabilities.
    false
  end

  def subtype_of?(ctx : Context, other : Nominal) : Bool
    # An anti-nominal can never be a subtype of any nominal -
    # it excludes a single nominal, and includes every other possible nominal,
    # so it cannot possibly be as or more specific than a single nominal.
    false
  end

  def supertype_of?(ctx : Context, other : Nominal) : Bool
    # An anti-nominal is a supertype of the given nominal if and only if
    # the other nominal is not a subtype of this defn's nominal.
    !other.subtype_of?(ctx, Nominal.new(defn))
  end

  def subtype_of?(ctx : Context, other : AntiNominal) : Bool
    # An anti-nominal is a subtype of another anti-nominal if and only if
    # all cases excluded by the other anti-nominal are also excluded by it.
    # For this anti-nominal to be as or more exclusive than the other,
    # its defn must be as or more inclusive than the other (a supertype).
    Nominal.new(other.defn).subtype_of?(ctx, Nominal.new(defn))
  end

  def supertype_of?(ctx : Context, other : AntiNominal) : Bool
    # This operation is symmetrical with the above operation.
    other.subtype_of?(ctx, self) # delegate to the above method via symmetry
  end

  def subtype_of?(ctx : Context, other : (Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def supertype_of?(ctx : Context, other : (Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def satisfies_bound?(ctx : Context, bound) : Bool
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end
end
