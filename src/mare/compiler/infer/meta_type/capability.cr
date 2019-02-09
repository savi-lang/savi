struct Mare::Compiler::Infer::MetaType::Capability
  getter name : String
  
  def initialize(@name)
  end
  
  ISO = new("iso"); def self.iso; ISO end
  TRN = new("trn"); def self.trn; TRN end
  REF = new("ref"); def self.ref; REF end
  VAL = new("val"); def self.val; VAL end
  BOX = new("box"); def self.box; BOX end
  TAG = new("tag"); def self.tag; TAG end
  NON = new("non"); def self.non; NON end
  
  def inspect(io : IO)
    io << name
  end
  
  def hash : UInt64
    name.hash
  end
  
  def ==(other)
    other.is_a?(Capability) && name == other.name
  end
  
  def each_reachable_defn : Iterator(Program::Type)
    ([] of Program::Type).each
  end
  
  def find_callable_func_defns(name : String)
    nil
  end
  
  def negate : Inner
    raise NotImplementedError.new("negate capability")
  end
  
  def intersect(other : Unconstrained)
    self
  end
  
  def intersect(other : Unsatisfiable)
    other
  end
  
  def intersect(other : Capability)
    return self if self == other
    
    # If one cap is a subtype of the other cap, return the subtype because
    # it is the most specific type of the two. Note that if they are
    # equivalent, it doesn't matter which we return here, but we'll return it.
    return self if self.subtype_of?(other)
    return other if other.subtype_of?(self)
    
    # If we reach this point, it's because we're dealing with `ref` and `val`.
    # Assert that this is the case, just for sanity's sake, then we will
    # return the `trn` capability, since it is the nearest subtype of both.
    raise "expected `ref` and `val`" \
      unless (REF == self && VAL == other) || (VAL == self && REF == other)
    TRN
  end
  
  def intersect(other : (Nominal | AntiNominal | Intersection | Union))
    other.intersect(self) # delegate to the "higher" class via commutativity
  end
  
  def unite(other : Unconstrained)
    other
  end
  
  def unite(other : Unsatisfiable)
    self
  end
  
  def unite(other : Capability)
    return self if self == other
    
    # TODO: Implement the rest of this method:
    raise NotImplementedError.new("#{self} | #{other}")
  end
  
  def unite(other : (Nominal | AntiNominal | Intersection | Union))
    other.unite(self) # delegate to the "higher" class via commutativity
  end
  
  def subtype_of?(other : Capability) : Bool
    ##
    # Reference capability subtyping can be visualized using this chart,
    # wherein leftward caps are subtypes of caps that appear to their right,
    # with ISO being a subtype of all, and NON being a supertype of all.
    #              / REF \
    # ISO <: TRN <:       <: BOX <: TAG <: NON
    #              \ VAL /
    
    # A capability always counts as a subtype of itself.
    return true if self == other
    
    # Otherwise, try to implement the rest of truth table in a readable way.
    case self
    when ISO # TODO: Take capability ephemerality into account.
      true
    when TRN # TODO: Take capability ephemerality into account.
      other != ISO
    when REF, VAL
      BOX == other || TAG == other || NON == other
    when BOX
      TAG == other || NON == other
    when TAG
      NON == other
    when NON
      false
    else
      raise NotImplementedError.new("#{self} < #{other}")
    end
  end
  
  def supertype_of?(other : Capability) : Bool
    other.subtype_of?(self) # delegate to the above function via symmetry
  end
  
  def subtype_of?(other : (Nominal | AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(self) # delegate to the other class via symmetry
  end
  
  def supertype_of?(other : (Nominal | AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(self) # delegate to the other class via symmetry
  end
end
