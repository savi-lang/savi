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
end
