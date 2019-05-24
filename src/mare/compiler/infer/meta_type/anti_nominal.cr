struct Mare::Compiler::Infer::MetaType::AntiNominal
  getter defn : Program::Type
  
  def initialize(@defn)
  end
  
  def inspect(io : IO)
    io << "-"
    io << defn.ident.value
    io << "'any"
  end
  
  def hash : UInt64
    self.class.hash ^ defn.hash
  end
  
  def ==(other)
    other.is_a?(AntiNominal) && defn == other.defn
  end
  
  def each_reachable_defn : Iterator(Program::Type)
    [defn].each # TODO: is an anti-nominal actually reachable?
  end
  
  def find_callable_func_defns(name : String)
    nil
  end
  
  def is_concrete?
    defn.is_concrete?
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
  
  def viewed_from(origin)
    raise NotImplementedError.new("#{origin.inspect}->#{self.inspect}")
  end
  
  def extracted_from(origin)
    raise NotImplementedError.new("#{origin.inspect}+>#{self.inspect}")
  end
  
  def subtype_of?(infer : Infer, other : Capability) : Bool
    # An anti-nominal can never be a subtype of any capability -
    # it excludes a single nominal, and says nothing about capabilities.
    false
  end
  
  def supertype_of?(infer : Infer, other : Capability) : Bool
    # An anti-nominal can never be a supertype of any capability -
    # it excludes a single nominal, and says nothing about capabilities.
    false
  end
  
  def subtype_of?(infer : Infer, other : Nominal) : Bool
    # An anti-nominal can never be a subtype of any nominal -
    # it excludes a single nominal, and includes every other possible nominal,
    # so it cannot possibly be as or more specific than a single nominal.
    false
  end
  
  def supertype_of?(infer : Infer, other : Nominal) : Bool
    # An anti-nominal is a supertype of the given nominal if and only if
    # the other nominal's defn is not a subtype of this nominal's defn.
    !infer.is_subtype?(other.defn, defn)
  end
  
  def subtype_of?(infer : Infer, other : AntiNominal) : Bool
    # An anti-nominal is a subtype of another anti-nominal if and only if
    # all cases excluded by the other anti-nominal are also excluded by it.
    # For this anti-nominal to be as or more exclusive than the other,
    # its defn must be as or more inclusive than the other (a supertype).
    infer.is_subtype?(other.defn, defn)
  end
  
  def supertype_of?(infer : Infer, other : AntiNominal) : Bool
    # This operation is symmetrical with the above operation.
    infer.is_subtype?(defn, other.defn)
  end
  
  def subtype_of?(infer : Infer, other : (Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(infer, self) # delegate to the other class via symmetry
  end
  
  def supertype_of?(infer : Infer, other : (Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(infer, self) # delegate to the other class via symmetry
  end
end
