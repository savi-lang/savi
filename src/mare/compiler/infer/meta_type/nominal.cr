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
  
  def find_callable_func_defns(name : String)
    func = defn.find_func?(name)
    [{defn, func}] if func
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
  
  def subtype_of?(other : Nominal) : Bool
    # A nominal is a subtype of another nominal if and only if
    # the defn is a subtype of the other defn.
    defn < other.defn
  end
  
  def supertype_of?(other : Nominal) : Bool
    # This operation is symmetrical with the above operation.
    other.defn < defn
  end
  
  def subtype_of?(other : (AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(self) # delegate to the other class via symmetry
  end
  
  def supertype_of?(other : (AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(self) # delegate to the other class via symmetry
  end
end
