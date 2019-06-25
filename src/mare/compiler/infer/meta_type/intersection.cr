struct Mare::Compiler::Infer::MetaType::Intersection
  getter cap : Capability?
  getter terms : Set(Nominal)?
  getter anti_terms : Set(AntiNominal)?
  
  def initialize(@cap = nil, @terms = nil, @anti_terms = nil)
    count = cap ? 1 : 0
    count += terms.try(&.size) || 0
    count += anti_terms.try(&.size) || 0
    
    raise "too few terms: #{inspect}" if count <= 1
    
    raise "empty terms" if terms && terms.try(&.empty?)
    raise "empty anti_terms" if anti_terms && anti_terms.try(&.empty?)
  end
  
  # This function works like .new, but it accounts for cases where there
  # aren't enough terms and anti-terms to build a real Intersection.
  # Returns Unconstrained if no terms or anti-terms are supplied.
  def self.build(
    cap : Capability? = nil,
    terms : Set(Nominal)? = nil,
    anti_terms : Set(AntiNominal)? = nil,
  ) : Inner
    count = cap ? 1 : 0
    count += terms.try(&.size) || 0
    count += anti_terms.try(&.size) || 0
    
    case count
    when 0 then Unconstrained.instance
    when 1
      cap || terms.try(&.first?) || anti_terms.not_nil!.first
    else
      terms = nil if terms && terms.empty?
      anti_terms = nil if anti_terms && anti_terms.empty?
      new(cap, terms, anti_terms)
    end
  end
  
  def inspect(io : IO)
    # If this intersection is just a term and capability, print abbreviated.
    if cap && terms.try(&.size) == 1 && anti_terms.nil?
      terms.not_nil!.first.inspect_with_cap(io, cap.not_nil!)
      return
    end
    
    first = true
    io << "("
    
    terms.not_nil!.each do |term|
      io << " & " unless first; first = false
      term.inspect(io)
    end if terms
    
    anti_terms.not_nil!.each do |anti_term|
      io << " & " unless first; first = false
      anti_term.inspect(io)
    end if anti_terms
    
    cap.try do |cap|
      io << " & " unless first; first = false
      cap.inspect(io)
    end
    
    io << ")"
  end
  
  def each_reachable_defn : Iterator(Infer::ReifiedType)
    iter = ([] of Infer::ReifiedType).each
    
    iter = iter.chain(
      terms.not_nil!.map(&.each_reachable_defn).flat_map(&.to_a).each
    ) if terms
    
    iter
  end
  
  def find_callable_func_defns(infer : ForFunc, name : String)
    list = [] of Tuple(Inner, Infer::ReifiedType?, Program::Function?)
    
    # Collect a result for nominal in this intersection that has this func.
    terms.try(&.each do |term|
      term.find_callable_func_defns(infer, name).try do |result|
        result.each do |_, defn, func|
          # Replace the inner term with an inner of this intersection.
          # This will be used for subtype checking later, and we want to
          # make sure that our cap will be taken into account, if any.
          list << {self, defn, func}
        end
      end
    end)
    
    # If none of the nominals in this intersection had the func,
    # we're in trouble; collect the list of types that failed our search.
    if list.empty?
      terms.try(&.each do |term|
        defn = term.defn
        list << {self, (defn if defn.is_a?(Infer::ReifiedType)), nil}
      end)
    end
    
    # If for some reason we're still empty (like in the case of an
    # intersection of anti-nominals), we have to return nil.
    list << {self, nil, nil} if list.empty?
    
    list
  end
  
  def any_callable_func_defn_type(name : String) : Infer::ReifiedType?
    # Return the first nominal in this intersection that has this func.
    terms.try(&.each do |term|
      term.any_callable_func_defn_type(name).try do |result|
        return result
      end
    end)
    
    nil
  end
  
  def negate : Inner
    # De Morgan's Law:
    # The negation of an intersection is the union of negations of its terms.
    
    new_cap = cap.try(&.negate)
    new_terms = anti_terms.try(&.map(&.negate).to_set) || Set(Nominal).new
    new_anti_terms = terms.try(&.map(&.negate).to_set) || Set(AntiNominal).new
    new_terms = nil if new_terms.empty?
    new_anti_terms = nil if new_anti_terms.empty?
    
    Union.new(new_cap, new_terms, new_anti_terms)
  end
  
  def intersect(other : Unconstrained)
    self
  end
  
  def intersect(other : Unsatisfiable)
    other
  end
  
  def intersect(other : Capability)
    new_cap = cap.try(&.intersect(other)) || other
    return self if new_cap == cap
    return new_cap if new_cap.is_a?(Unsatisfiable)
    
    Intersection.new(new_cap, terms, anti_terms)
  end
  
  def intersect(other : Nominal)
    # No change if we've already intersected with this type.
    return self if terms && terms.not_nil!.includes?(other)
    
    # Unsatisfiable if we have already have an anti-term for this type.
    return Unsatisfiable.instance \
      if anti_terms && anti_terms.not_nil!.includes?(AntiNominal.new(other.defn))
    
    # Unsatisfiable if there are two non-identical concrete types.
    return Unsatisfiable.instance \
      if other.is_concrete? && terms && terms.not_nil!.any?(&.is_concrete?)
    
    # Add this to existing terms (if any) and create the intersection.
    new_terms =
      if terms
        terms.not_nil!.dup.add(other)
      else
        [other].to_set
      end
    Intersection.new(cap, new_terms, anti_terms)
  end
  
  def intersect(other : AntiNominal)
    # No change if we've already intersected with this anti-type.
    return self if anti_terms && anti_terms.not_nil!.includes?(other)
    
    # Unsatisfiable if we have already have a term for this anti-type.
    return Unsatisfiable.instance \
      if terms && terms.not_nil!.includes?(Nominal.new(other.defn))
    
    # Add this to existing anti-terms (if any) and create the intersection.
    new_anti_terms =
      if anti_terms
        anti_terms.not_nil!.dup.add(other)
      else
        [other].to_set
      end
    Intersection.new(cap, terms, new_anti_terms)
  end
  
  def intersect(other : Intersection)
    # Intersect each individual term of other into this running intersection.
    # If the result becomes Unsatisfiable, return so immediately.
    result = self
    other.cap.try do |cap|
      result = result.intersect(cap)
      return result if result.is_a?(Unsatisfiable)
    end
    other.terms.not_nil!.each do |term|
      result = result.intersect(term)
      return result if result.is_a?(Unsatisfiable)
    end if other.terms
    other.anti_terms.not_nil!.each do |term|
      result = result.intersect(term)
      return result if result.is_a?(Unsatisfiable)
    end if other.anti_terms
    
    # Return the fully intersected result.
    result
  end
  
  def intersect(other : Union)
    other.intersect(self) # delegate to the "higher" class via commutativity
  end
  
  def unite(other : Unconstrained)
    other
  end
  
  def unite(other : Unsatisfiable)
    self
  end
  
  def unite(other : Capability)
    Union.new([other].to_set, nil, nil, [self].to_set)
  end
  
  def unite(other : Nominal)
    Union.new(nil, [other].to_set, nil, [self].to_set)
  end
  
  def unite(other : AntiNominal)
    Union.new(nil, nil, [other].to_set, [self].to_set)
  end
  
  def unite(other : Intersection)
    return self if self == other
    
    Union.new(nil, nil, nil, [self, other].to_set)
  end
  
  def unite(other : Union)
    other.unite(self) # delegate to the "higher" class via commutativity
  end
  
  def ephemeralize
    Intersection.new(cap.try(&.ephemeralize), terms, anti_terms)
  end
  
  def strip_ephemeral
    Intersection.new(cap.try(&.strip_ephemeral), terms, anti_terms)
  end
  
  def alias
    Intersection.new(cap.try(&.alias), terms, anti_terms)
  end
  
  def strip_cap
    Intersection.build(nil, terms, anti_terms)
  end
  
  def partial_reifications
    cap = cap()
    
    # If this intersection already has a single capability, it can't be divided
    # into any further capability possibilities, so just return it now.
    return [self] if cap && cap.value.is_a?(String)
    
    # Otherwise, we need to intersect with every possible non-ephemeral cap.
    Capability::ALL_NON_EPH
      .map(&.intersect(self))
      .reject(&.is_a?(Unsatisfiable))
      .to_set
  end
  
  def type_params
    result = Set(Refer::TypeParam).new
    
    terms.not_nil!.each do |term|
      result.concat(term.type_params)
    end if terms
    anti_terms.not_nil!.each do |anti_term|
      result.concat(anti_term.type_params)
    end if anti_terms
    
    result
  end
  
  def is_sendable?
    cap.try(&.is_sendable?) || false
  end
  
  def viewed_from(origin)
    raise NotImplementedError.new("#{origin.inspect}->(nil cap)") unless cap
    
    Intersection.new(Capability::NON, terms, anti_terms)
      .intersect(cap.not_nil!.viewed_from(origin))
  end
  
  def extracted_from(origin)
    raise NotImplementedError.new("#{origin.inspect}+>(nil cap)") unless cap
    
    Intersection.new(Capability::NON, terms, anti_terms)
      .intersect(cap.not_nil!.extracted_from(origin))
  end
  
  def subtype_of?(infer : ForFunc, other : Capability) : Bool
    # This intersection is a subtype of the given capability if and only if
    # it has a capability as part of the intersection, and that capability
    # is a subtype of the given capability.
    cap.try(&.subtype_of?(infer, other)) || false
  end
  
  def supertype_of?(infer : ForFunc, other : Capability) : Bool
    # If we have terms or anti-terms, we can't possibly be a supertype of other,
    # because a capability can never be a subtype of a nominal or anti-nominal.
    return false if terms || anti_terms
    
    raise NotImplementedError.new([self, :supertype_of?, other].inspect)
  end
  
  def subtype_of?(infer : ForFunc, other : Nominal) : Bool
    # Note that no matter if we have a capability restriction or not,
    # it doesn't factor into us considering whether we're a subtype of
    # the given nominal or not - a nominal says nothing about capabilities.
    
    # This intersection is a subtype of the given nominal if and only if
    # all terms in the intersection are a supertype of that nominal.
    result = true
    result &&= terms.not_nil!.all?(&.subtype_of?(infer, other)) if terms
    result &&= anti_terms.not_nil!.all?(&.subtype_of?(infer, other)) if anti_terms
    result
  end
  
  def supertype_of?(infer : ForFunc, other : Nominal) : Bool
    # If we have a capability restriction, we can't possibly be a supertype of
    # other, because a nominal says nothing about capabilities.
    return false if cap
    
    # This intersection is a supertype of the given nominal if and only if
    # all terms in the intersection are a supertype of that nominal.
    result = true
    result &&= terms.not_nil!.all?(&.supertype_of?(infer, other)) if terms
    result &&= anti_terms.not_nil!.all?(&.supertype_of?(infer, other)) if anti_terms
    result
  end
  
  def subtype_of?(infer : ForFunc, other : AntiNominal) : Bool
    raise NotImplementedError.new([self, :subtype_of?, other].inspect)
  end
  
  def supertype_of?(infer : ForFunc, other : AntiNominal) : Bool
    raise NotImplementedError.new([self, :supertype_of?, other].inspect)
  end
  
  def subtype_of?(infer : ForFunc, other : Intersection) : Bool
    # Firstly, our cap must be a subtype of the other cap (if present).
    return false if other.cap && (
      !cap ||
      !cap.not_nil!.subtype_of?(infer, other.cap.not_nil!)
    )
    
    # Next, we'll look at each term we have.
    terms.try(&.each do |term|
      # The term must be a subtype of all terms in the other.
      # TODO: we may have to do something more subtle here when dealing with
      # subtyping of intersections of traits, where multiple traits
      # get inlined into a single composite trait so that they can be
      # properly compared while taking it all simultaneously into account.
      return false \
        if other.terms && !other.terms.not_nil!.all?(&.supertype_of?(infer, term))
      
      raise NotImplementedError.new("intersection subtyping with anti terms") \
        if other.anti_terms
    end)
    
    # Next, we'll look at each anti-term we have.
    anti_terms.try(&.each do |anti_term|
      raise NotImplementedError.new("intersection subtyping with anti terms")
    end)
    
    # If we reach this point, we've passed all checks. Congratulations!
    true
  end
  
  def supertype_of?(infer : ForFunc, other : Intersection) : Bool
    other.subtype_of?(infer, self) # delegate to the above function via symmetry.
  end
  
  def subtype_of?(infer : ForFunc, other : (Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(infer, self) # delegate to the other class via symmetry
  end
  
  def supertype_of?(infer : ForFunc, other : (Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(infer, self) # delegate to the other class via symmetry
  end
  
  def satisfies_bound?(infer : (ForFunc | ForType), bound : Capability) : Bool
    # This intersection satisfies the given capability bound if and only if
    # it has a capability as part of the intersection, and that capability
    # is satisfies the given capability bound.
    cap.try(&.satisfies_bound?(infer, bound)) || false
  end
  
  def satisfies_bound?(infer : (ForFunc | ForType), bound : (Nominal | AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end
end
