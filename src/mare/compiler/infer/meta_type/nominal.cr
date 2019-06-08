struct Mare::Compiler::Infer::MetaType::Nominal
  getter defn : Infer::ReifiedType | Refer::DeclParam
  
  def initialize(@defn)
  end
  
  def inspect(io : IO)
    inspect_without_cap(io)
    
    io << "'any"
  end
  
  def inspect_with_cap(io : IO, cap : Capability)
    inspect_without_cap(io)
    
    # If the cap is the same as the default cap, we omit it for brevity.
    # Otherwise, we'll print it here with the same syntax that the programmer
    # can use to specify it explicitly.
    defn = defn()
    unless defn.is_a?(Infer::ReifiedType) && cap.value == defn.defn.cap.value
      io << "'"
      cap.inspect(io)
    end
  end
  
  def inspect_without_cap(io : IO)
    defn = defn()
    case defn
    when Infer::ReifiedType
      defn.show_type(io)
    when Refer::DeclParam
      io << defn.ident.value
    end
  end
  
  def each_reachable_defn : Iterator(Infer::ReifiedType)
    defn = defn()
    defn.is_a?(Infer::ReifiedType) ? [defn].each : ([] of Infer::ReifiedType).each
  end
  
  def find_callable_func_defns(infer : ForFunc, name : String)
    defn = defn()
    case defn
    when Infer::ReifiedType
      func = defn.defn.find_func?(name)
      [{self, defn, func}] if func
    when Refer::DeclParam
      raise NotImplementedError.new("TODO in this commit")
    else raise NotImplementedError.new(defn)
    end
  end
  
  def any_callable_func_defn_type(name : String) : Infer::ReifiedType?
    defn = defn()
    if defn.is_a?(Infer::ReifiedType)
      func = defn.defn.find_func?(name)
      defn if func
    end
  end
  
  def is_concrete?
    defn = defn()
    defn.is_a?(Infer::ReifiedType) && defn.defn.is_concrete?
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
  
  def intersect(other : Capability)
    Intersection.new(other, [self].to_set)
  end
  
  def intersect(other : Nominal)
    # No change if the two nominal types are identical.
    return self if defn == other.defn
    
    # Unsatisfiable if the two are concrete types that are not identical.
    return Unsatisfiable.instance if is_concrete? && other.is_concrete?
    
    # Otherwise, this is a new intersection of the two types.
    Intersection.new(nil, [self, other].to_set)
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
  
  def unite(other : Capability)
    Union.new([other].to_set, [self].to_set)
  end
  
  def unite(other : Nominal)
    # No change if the two nominal types are identical.
    return self if defn == other.defn
    
    # Otherwise, this is a new union of the two types.
    Union.new(nil, [self, other].to_set)
  end
  
  def unite(other : (AntiNominal | Intersection | Union))
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
  
  def is_sendable?
    # An nominal is never itself sendable -
    # it specifies a single nominal, and says nothing about capabilities.
    false
  end
  
  def viewed_from(origin)
    raise NotImplementedError.new("#{origin.inspect}->#{self.inspect}")
  end
  
  def extracted_from(origin)
    raise NotImplementedError.new("#{origin.inspect}+>#{self.inspect}")
  end
  
  def subtype_of?(infer : ForFunc, other : Capability) : Bool
    # A nominal can never be a subtype of any capability -
    # it specifies a single nominal, and says nothing about capabilities.
    false
  end
  
  def supertype_of?(infer : ForFunc, other : Capability) : Bool
    # A nominal can never be a supertype of any capability -
    # it specifies a single nominal, and says nothing about capabilities.
    false
  end
  
  def subtype_of?(infer : ForFunc, other : Nominal) : Bool
    # A nominal is a subtype of another nominal if and only if
    # the defn is a subtype of the other defn.
    infer.is_subtype?(defn, other.defn)
  end
  
  def supertype_of?(infer : ForFunc, other : Nominal) : Bool
    # This operation is symmetrical with the above operation.
    infer.is_subtype?(other.defn, defn)
  end
  
  def subtype_of?(infer : ForFunc, other : (AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(infer, self) # delegate to the other class via symmetry
  end
  
  def supertype_of?(infer : ForFunc, other : (AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(infer, self) # delegate to the other class via symmetry
  end
  
  def satisfies_bound?(infer : (ForFunc | ForType), bound) : Bool
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end
end
