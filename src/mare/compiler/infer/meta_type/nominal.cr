struct Mare::Compiler::Infer::MetaType::Nominal
  getter defn : Program::Type
  
  def initialize(@defn)
  end
  
  def inspect(io : IO)
    io << defn.ident.value
  end
  
  def hash : UInt64
    defn.hash
  end
  
  def ==(other)
    other.is_a?(Nominal) && defn == other.defn
  end
  
  def each_reachable_defn : Iterator(Program::Type)
    [defn].each
  end
  
  def is_concrete?
    defn.is_concrete?
  end
  
  def negate : Inner
    AntiNominal.new(defn)
  end
  
  def intersect(other : Unconstrained)
    self
  end
  
  def intersect(other : Unsatisfiable)
    other
  end
  
  def intersect(other : Nominal)
    # No change if the two nominal types are identical.
    return self if defn == other.defn
    
    # Unsatisfiable if the two are concrete types that are not identical.
    return Unsatisfiable.instance if is_concrete? && other.is_concrete?
    
    # Otherwise, this is a new intersection of the two types.
    Intersection.new([self, other].to_set)
  end
  
  def intersect(other : (AntiNominal | Intersection | Union))
    other.intersect(self) # delegate to the "higher" class via commutativity
  end
  
  def unite(other : Unconstrained)
    other
  end
  
  def unite(other : Unsatisfiable)
    self
  end
  
  def unite(other : Nominal)
    # No change if the two nominal types are identical.
    return self if defn == other.defn
    
    # Otherwise, this is a new union of the two types.
    Union.new([self, other].to_set)
  end
  
  def unite(other : (AntiNominal | Intersection | Union))
    other.unite(self) # delegate to the "higher" class via commutativity
  end
end
