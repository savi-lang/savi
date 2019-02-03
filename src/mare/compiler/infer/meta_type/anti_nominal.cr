struct Mare::Compiler::Infer::MetaType::AntiNominal
  getter defn : Program::Type
  
  def initialize(@defn)
  end
  
  def inspect(io : IO)
    io << "-"
    io << defn.ident.value
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
  
  def intersect(other : Nominal)
    # Unsatisfiable if the nominal and anti-nominal types are identical.
    return Unsatisfiable.instance if defn == other.defn
    
    # Otherwise, this is a new intersection of the two types.
    Intersection.new([other].to_set, [self].to_set)
  end
  
  def intersect(other : AntiNominal)
    # No change if the two anti-nominal types are identical.
    return self if defn == other.defn
    
    # Otherwise, this is a new intersection of the two types.
    Intersection.new(Set(Nominal).new, [self, other].to_set)
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
  
  def unite(other : Nominal)
    # Unconstrained if the nominal and anti-nominal types are identical.
    return Unconstrained.instance if defn == other.defn
    
    # Otherwise, this is a new union of the two types.
    Union.new([other].to_set, [self].to_set)
  end
  
  def unite(other : AntiNominal)
    # No change if the two anti-nominal types are identical.
    return self if defn == other.defn
    
    # Unconstrained if the two are concrete types that are not identical.
    return Unconstrained.instance if is_concrete? && other.is_concrete?
    
    # Otherwise, this is a new union of the two types.
    Union.new(Set(Nominal).new, [self, other].to_set)
  end
  
  def unite(other : (Intersection | Union))
    other.unite(self) # delegate to the "higher" class via commutativity
  end
  
  def subtype_of?(other : Nominal) : Bool
    # An anti-nominal can never be a subtype of any nominal -
    # it excludes a single nominal, and includes every other possible nominal,
    # so it cannot possibly be as or more specific than a single nominal.
    false
  end
  
  def supertype_of?(other : Nominal) : Bool
    # An anti-nominal is a supertype of the given nominal if and only if
    # the other nominal's defn is not a subtype of this nominal's defn.
    !(other.defn < defn)
  end
  
  def subtype_of?(other : AntiNominal) : Bool
    # An anti-nominal is a subtype of another anti-nominal if and only if
    # all cases excluded by the other anti-nominal are also excluded by it.
    # For this anti-nominal to be as or more exclusive than the other,
    # its defn must be as or more inclusive than the other (a supertype).
    other.defn < defn
  end
  
  def supertype_of?(other : AntiNominal) : Bool
    # This operation is symmetrical with the above operation.
    defn < other.defn
  end
  
  def subtype_of?(other : (Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(self) # delegate to the other class via symmetry
  end
  
  def supertype_of?(other : (Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(self) # delegate to the other class via symmetry
  end
end
