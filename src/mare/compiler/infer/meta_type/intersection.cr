struct Mare::Compiler::Infer::MetaType::Intersection
  getter terms : Set(Nominal)
  getter anti_terms : Set(AntiNominal)?
  
  def initialize(@terms, @anti_terms = nil)
    raise "too few terms: #{terms.inspect}, #{@anti_terms.inspect}" \
      if (@terms.size + (@anti_terms.try(&.size) || 0)) <= 1
  end
  
  # This function works like .new, but it accounts for cases where there
  # aren't enough terms and anti-terms to build a real Intersection.
  # Returns Unconstrained if no terms or anti-terms are supplied.
  def self.build(
    terms : Set(Nominal),
    anti_terms : Set(AntiNominal)? = nil,
  ) : Inner
    if terms.size == 0
      case (anti_terms.try(&.size) || 0)
      when 0 then return Unconstrained.instance
      when 1 then return anti_terms.not_nil!.first
      end
    elsif (terms.size == 1) && ((anti_terms.try(&.size) || 0) == 0)
      return terms.first
    end
    
    anti_terms = nil if anti_terms && anti_terms.empty?
    new(terms, anti_terms)
  end
  
  def inspect(io : IO)
    first = true
    io << "("
    
    terms.each do |term|
      io << " & " unless first; first = false
      term.inspect(io)
    end
    
    anti_terms.not_nil!.each do |anti_term|
      io << " & " unless first; first = false
      anti_term.inspect(io)
    end if anti_terms
    
    io << ")"
  end
  
  def hash : UInt64
    hash = terms.hash
    hash ^= (anti_terms.not_nil!.hash * 31) if anti_terms
    hash
  end
  
  def ==(other)
    other.is_a?(Intersection) &&
    terms == other.terms &&
    anti_terms == other.anti_terms
  end
  
  def each_reachable_defn : Iterator(Program::Type)
    iter = terms.each.map(&.defn)
    
    return iter unless anti_terms
    iter = iter.chain(anti_terms.not_nil!.each.map(&.defn)) # TODO: is an anti-nominal actually reachable?
  end
  
  def find_callable_func_defns(name : String)
    # We return for only those in the intersection that have this func.
    list = [] of Tuple(Program::Type, Program::Function)
    terms.each do |term|
      result = term.find_callable_func_defns(name)
      list.concat(result) if result
    end
    list.empty? ? nil : list
  end
  
  def negate : Inner
    # De Morgan's Law:
    # The negation of an intersection is the union of negations of its terms.
    
    new_terms = anti_terms.try(&.map(&.negate).to_set) || Set(Nominal).new
    new_anti_terms = terms.map(&.negate).to_set
    new_anti_terms = nil if new_anti_terms.empty?
    
    Union.new(new_terms, new_anti_terms)
  end
  
  def intersect(other : Unconstrained)
    self
  end
  
  def intersect(other : Unsatisfiable)
    other
  end
  
  def intersect(other : Nominal)
    # No change if we've already intersected with this type.
    return self if terms.includes?(other)
    
    # Unsatisfiable if we have already have an anti-term for this type.
    return Unsatisfiable.instance \
      if anti_terms && anti_terms.not_nil!.includes?(AntiNominal.new(other.defn))
    
    # Unsatisfiable if there are two non-identical concrete types.
    return Unsatisfiable.instance \
      if other.is_concrete? && terms.any?(&.is_concrete?)
    
    # Otherwise, create a new intersection that adds this type.
    Intersection.new(terms.dup.add(other), anti_terms)
  end
  
  def intersect(other : AntiNominal)
    # No change if we've already intersected with this anti-type.
    return self if anti_terms && anti_terms.not_nil!.includes?(other)
    
    # Unsatisfiable if we have already have a term for this anti-type.
    return Unsatisfiable.instance if terms.includes?(Nominal.new(other.defn))
    
    # Add this to existing anti-terms (if any) and create the intersection.
    new_anti_terms =
      if anti_terms
        anti_terms.not_nil!.dup.add(other)
      else
        [other].to_set
      end
    Intersection.new(terms, new_anti_terms)
  end
  
  def intersect(other : Intersection)
    # Intersect each individual term of other into this running intersection.
    # If the result becomes Unsatisfiable, return so immediately.
    result = self
    other.terms.each do |term|
      result = result.intersect(term)
      return result if result.is_a?(Unsatisfiable)
    end
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
  
  def unite(other : Nominal)
    Union.new([other].to_set, nil, [self].to_set)
  end
  
  def unite(other : AntiNominal)
    Union.new(Set(Nominal).new, [other].to_set, [self].to_set)
  end
  
  def unite(other : Intersection)
    return self if self == other
    
    Union.new(Set(Nominal).new, nil, [self, other].to_set)
  end
  
  def unite(other : Union)
    other.unite(self) # delegate to the "higher" class via commutativity
  end
  
  def subtype_of?(other : Nominal) : Bool
    raise NotImplementedError.new([self, :subtype_of?, other].inspect)
  end
  
  def supertype_of?(other : Nominal) : Bool
    # This intersection is a supertype of the given nominal if and only if
    # all terms in the intersection are a supertype of that nominal.
    result = terms.all?(&.supertype_of?(other))
    result &&= anti_terms.not_nil!.all?(&.supertype_of?(other)) if anti_terms
    result
  end
  
  def subtype_of?(other : AntiNominal) : Bool
    raise NotImplementedError.new([self, :subtype_of?, other].inspect)
  end
  
  def supertype_of?(other : AntiNominal) : Bool
    raise NotImplementedError.new([self, :supertype_of?, other].inspect)
  end
  
  def subtype_of?(other : Intersection) : Bool
    raise NotImplementedError.new([self, :subtype_of?, other].inspect)
  end
  
  def supertype_of?(other : Intersection) : Bool
    raise NotImplementedError.new([self, :supertype_of?, other].inspect)
  end
  
  def subtype_of?(other : (Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(self) # delegate to the other class via symmetry
  end
  
  def supertype_of?(other : (Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(self) # delegate to the other class via symmetry
  end
end
