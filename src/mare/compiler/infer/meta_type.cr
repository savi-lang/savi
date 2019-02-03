class Mare::Compiler::Infer::MetaType
  ##
  # A MetaType is represented internally in Disjunctive Normal Form (DNF),
  # which is a standardized precedence order of logical formula that is
  # conducive to formal subtype checking without too many edge cases.
  #
  # The precedence order for DNF is OR > AND > NOT, such that the lowest level
  # term (a nominal type) can be optionally contained within a "NOT" term
  # (which we call an anti-nominal type), which can be optionally within
  # an "AND" term (a type intersection), which can be optionally within
  # an "OR" term (a type union).
  #
  # If we ever get an operation that breaks this order of precedence, such as
  # if we were asked to intersect two unions, or negate an intersection, we
  # have to redistribute the terms and simplify to reach the DNF form.
  # We ensure this is always done by representing the Inner types in this way.
  
  struct Union;        end # A type union - a logical "OR".
  struct Intersection; end # A type intersection - a logical "AND".
  struct AntiNominal;  end # A type negation - a logical "NOT".
  struct Nominal;      end # A named type, either abstract or concrete.
  class Unsatisfiable; end # It's impossible to find a type that fulfills this.
  class Unconstrained; end # All types fulfill this - totally unconstrained.
  
  alias Inner = (
    Union | Intersection | AntiNominal | Nominal |
    Unsatisfiable | Unconstrained)
  
  class Unconstrained
    INSTANCE = new
    
    def self.instance
      INSTANCE
    end
    
    private def self.new
      super
    end
    
    def inspect(io : IO)
      io << "<unconstrained>"
    end
    
    def hash : UInt64
      self.class.hash
    end
    
    def ==(other)
      other.is_a?(Unconstrained)
    end
    
    def each_reachable_defn : Iterator(Program::Type)
      ([] of Program::Type).each
    end
    
    def negate : Inner
      # The negation of an Unconstrained is... well... I'm not sure yet.
      # Is it Unsatisfiable?
      raise NotImplementedError.new("negation of #{inspect}")
    end
    
    def intersect(other : Inner)
      # The intersection of Unconstrained and anything is the other thing.
      other
    end
    
    def unite(other : Inner)
      # The union of Unconstrained and anything is still Unconstrained.
      self
    end
  end
  
  class Unsatisfiable
    INSTANCE = new
    
    def self.instance
      INSTANCE
    end
    
    private def self.new
      super
    end
    
    def inspect(io : IO)
      io << "<unsatisfiable>"
    end
    
    def hash : UInt64
      self.class.hash
    end
    
    def ==(other)
      other.is_a?(Unsatisfiable)
    end
    
    def each_reachable_defn : Iterator(Program::Type)
      ([] of Program::Type).each
    end
    
    def negate : Inner
      # The negation of an Unsatisfiable is... well... I'm not sure yet.
      # Is it Unconstrained?
      raise NotImplementedError.new("negation of #{inspect}")
    end
    
    def intersect(other : Inner)
      # The intersection of Unsatisfiable and anything is still Unsatisfiable.
      self
    end
    
    def unite(other : Inner)
      # The union of Unsatisfiable and anything is the other thing.
      other
    end
  end
  
  struct Nominal
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
  
  struct AntiNominal
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
  
  struct Intersection
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
  end
  
  struct Union
    getter terms : Set(Nominal)
    getter anti_terms : Set(AntiNominal)?
    getter intersects : Set(Intersection)?
    
    def initialize(@terms, @anti_terms = nil, @intersects = nil)
      raise "too few terms: #{inspect}" \
        if (@terms.size +
          (@anti_terms.try(&.size) || 0) +
          (@intersects.try(&.size) || 0)
        ) <= 1
    end
    
    # This function works like .new, but it accounts for cases where there
    # aren't enough terms, anti-terms, and intersections to build a real Union.
    # Returns Unsatisfiable if no terms or anti-terms are supplied.
    def self.build(
      terms : Set(Nominal),
      anti_terms : Set(AntiNominal)? = nil,
      intersects : Set(Intersection)? = nil,
    ) : Inner
      if terms.size == 0
        if (anti_terms.try(&.size) || 0) == 0
          case (intersects.try(&.size) || 0)
          when 0 then return Unsatisfiable.instance
          when 1 then return intersects.not_nil!.first
          end
        elsif (intersects.try(&.size) || 0) == 0
          if anti_terms.not_nil!.size == 1
            return anti_terms.not_nil!.first
          end
        end
      elsif (terms.size == 1) \
        && ((anti_terms.try(&.size) || 0) == 0) \
        && ((intersects.try(&.size) || 0) == 0)
        return terms.first
      end
      
      anti_terms = nil if anti_terms && anti_terms.empty?
      intersects = nil if intersects && intersects.empty?
      
      new(terms, anti_terms, intersects)
    end
    
    def inspect(io : IO)
      first = true
      io << "("
      
      terms.each do |term|
        io << " | " unless first; first = false
        term.inspect(io)
      end
      
      anti_terms.not_nil!.each do |anti_term|
        io << " | " unless first; first = false
        anti_term.inspect(io)
      end if anti_terms
      
      intersects.not_nil!.each do |intersect|
        io << " | " unless first; first = false
        intersect.inspect(io)
      end if intersects
      
      io << ")"
    end
    
    def hash : UInt64
      hash = terms.hash
      hash ^= (anti_terms.not_nil!.hash * 31) if anti_terms
      hash ^= (intersects.not_nil!.hash * 63) if intersects
      hash
    end
    
    def ==(other)
      other.is_a?(Union) &&
      terms == other.terms &&
      anti_terms == other.anti_terms &&
      intersects == other.intersects
    end
    
    def each_reachable_defn : Iterator(Program::Type)
      iter = terms.each.map(&.defn)
      
      return iter unless anti_terms
      iter = iter.chain(anti_terms.not_nil!.each.map(&.defn)) # TODO: is an anti-nominal actually reachable?
      
      return iter unless intersects
      iter = iter.chain(
        intersects.not_nil!.map(&.each_reachable_defn).flat_map(&.to_a).each
      )
    end
    
    def negate : Inner
      # De Morgan's Law:
      # The negation of a union is the intersection of negations of its terms.
      result = nil
      terms.each do |term|
        term = term.negate
        result = result ? result.intersect(term) : term
        return result if result.is_a?(Unsatisfiable)
      end
      anti_terms.not_nil!.each do |anti_term|
        anti_term = anti_term.negate
        result = result ? result.intersect(anti_term) : anti_term
        return result if result.is_a?(Unsatisfiable)
      end if anti_terms
      intersects.not_nil!.each do |intersect|
        intersect = intersect.negate
        result = result ? result.intersect(intersect) : intersect
        return result if result.is_a?(Unsatisfiable)
      end if intersects
      
      result.not_nil!
    end
    
    def intersect(other : Unconstrained)
      self
    end
    
    def intersect(other : Unsatisfiable)
      other
    end
    
    def intersect(other : (Nominal | AntiNominal | Intersection | Union))
      # Intersect the other with each term that we contain in the union,
      # discarding any results that come back as Unsatisfiable intersections.
      results = [] of Inner
      terms.each do |term|
        result = other.intersect(term)
        results << result unless result.is_a?(Unsatisfiable)
      end
      anti_terms.not_nil!.each do |anti_term|
        result = other.intersect(anti_term)
        results << result unless result.is_a?(Unsatisfiable)
      end if anti_terms
      intersects.not_nil!.each do |intersect|
        result = other.intersect(intersect)
        results << result unless result.is_a?(Unsatisfiable)
      end if intersects
      
      # Finally, unite all of the intersections together into their union.
      result = Unsatisfiable.instance
      results.each { |x| result = result.unite(x) }
      result
    end
    
    def unite(other : Unconstrained)
      other
    end
    
    def unite(other : Unsatisfiable)
      self
    end
    
    def unite(other : Nominal)
      # No change if we've already united with this type.
      return self if terms.includes?(other)
      
      # Unconstrained if we have already have an anti-term for this type.
      return Unconstrained.instance \
        if anti_terms && anti_terms.not_nil!.includes?(AntiNominal.new(other.defn))
      
      # Otherwise, create a new union that adds this type.
      Union.new(terms.dup.add(other), anti_terms, intersects)
    end
    
    def unite(other : AntiNominal)
      # No change if we've already united with this anti-type.
      return self if anti_terms && anti_terms.not_nil!.includes?(other)
      
      # Unconstrained if we have already have a term for this anti-type.
      return Unconstrained.instance if terms.includes?(Nominal.new(other.defn))
      
      # Unconstrained if there are two non-identical concrete anti-types.
      return Unconstrained.instance \
        if other.is_concrete? \
          && anti_terms && anti_terms.not_nil!.any?(&.is_concrete?)
      
      # Add this to existing anti-terms (if any) and create the union.
      new_anti_terms =
        if anti_terms
          anti_terms.not_nil!.dup.add(other)
        else
          [other].to_set
        end
      Union.new(terms, new_anti_terms, intersects)
    end
    
    def unite(other : Intersection)
      # No change if we already have an equivalent intersection.
      return self if intersects && intersects.not_nil!.includes?(other)
      
      # Add this to existing anti-terms (if any) and create the union.
      new_intersects =
        if intersects
          intersects.not_nil!.dup.add(other)
        else
          [other].to_set
        end
      Union.new(terms, anti_terms, new_intersects)
    end
    
    def unite(other : Union)
      # Intersect each individual term of other into this running union.
      # If the result becomes Unconstrained, return so immediately.
      result : Inner = self
      other.terms.each do |term|
        result = result.unite(term)
        return result if result.is_a?(Unconstrained)
      end
      other.anti_terms.not_nil!.each do |anti_term|
        result = result.unite(anti_term)
        return result if result.is_a?(Unconstrained)
      end if other.anti_terms
      other.intersects.not_nil!.each do |intersect|
        result = result.unite(intersect)
        return result if result.is_a?(Unconstrained)
      end if other.intersects
      
      result
    end
  end
  
  getter inner : Inner
  
  def initialize(@inner)
  end
  
  def initialize(nominal : Program::Type)
    @inner = Nominal.new(nominal)
  end
  
  def initialize(union : Enumerable(Program::Type))
    if union.size == 0
      @inner = Unsatisfiable.instance
    elsif union.size == 1
      @inner = Nominal.new(union.first)
    else
      @inner = Union.new(union.map { |d| Nominal.new(d) }.to_set)
    end
  end
  
  def self.new_union(types : Iterable(MetaType))
    inner = Unsatisfiable.instance
    types.each { |mt| inner = inner.unite(mt.inner) }
    MetaType.new(inner)
  end
  
  # TODO: remove this method:
  def defns : Enumerable(Program::Type)
    inner = @inner
    case inner
    when Unsatisfiable
      [] of Program::Type
    when Nominal
      [inner.defn]
    when Union
      raise NotImplementedError.new(inner.inspect) \
        if inner.anti_terms || inner.intersects
      inner.terms.map(&.defn)
    else raise NotImplementedError.new(inner.inspect)
    end
  end
  
  def unsatisfiable?
    @inner.is_a?(Unsatisfiable)
  end
  
  def singular?
    @inner.is_a?(Nominal)
  end
  
  def single!
    raise "not singular: #{show_type}" unless singular?
    @inner.as(Nominal).defn
  end
  
  def -; negate end
  def negate
    MetaType.new(@inner.negate)
  end
  
  def &(other : MetaType); intersect(other) end
  def intersect(other : MetaType)
    MetaType.new(@inner.intersect(other.inner))
  end
  
  def |(other : MetaType); unite(other) end
  def unite(other : MetaType)
    MetaType.new(@inner.unite(other.inner))
  end
  
  def simplify
    inner = @inner
    
    # Currently we only have the logic to simplify these cases:
    return MetaType.new(simplify_union(inner)) if inner.is_a?(Union) && inner.intersects
    return MetaType.new(simplify_intersection(inner)) if inner.is_a?(Intersection)
    
    self
  end
  
  private def simplify_intersection(inner : Intersection)
    # TODO: complete the rest of the logic here (think about symmetry)
    removed_terms = Set(Nominal).new
    new_terms = inner.terms.select do |l|
      # Return Unsatisfiable if any term is a subtype of an anti-term.
      if inner.anti_terms && inner.anti_terms.not_nil!.any? do |r|
        self.class.is_l_defn_sub_r_defn?(l.defn, r.defn)
      end
        return Unsatisfiable.instance
      end
      
      # Return Unsatisfiable if l is concrete and isn't a subtype of any other.
      if l.is_concrete? && inner.terms.any? do |r|
        !self.class.is_l_defn_sub_r_defn?(l.defn, r.defn)
      end
        return Unsatisfiable.instance
      end
      
      # Remove terms that are supertypes of another term - they are redundant.
      if inner.terms.any? do |r|
        l != r &&
        !removed_terms.includes?(r) &&
        self.class.is_l_defn_sub_r_defn?(r.defn, l.defn)
      end
        removed_terms.add(l)
        next
      end
      
      true # keep this term
    end
    
    # If we didn't remove anything, there was no change.
    return inner if removed_terms.empty?
    
    # Otherwise, return as a new intersection.
    Intersection.build(new_terms.to_set, inner.anti_terms)
  end
  
  private def simplify_union(inner : Union)
    terms = Set(Nominal).new
    anti_terms = Set(AntiNominal).new
    intersects = Set(Intersection).new
    
    # Just copy the terms and anti-terms without working with them.
    # TODO: are there any simplifications we can/should apply here?
    # TODO: consider some that are in symmetry with those for intersections.
    terms.concat(inner.terms)
    anti_terms.concat(inner.anti_terms.not_nil!) if inner.anti_terms
    
    # Simplify each intersection, collecting the results.
    inner.intersects.not_nil!.each do |intersect|
      result = simplify_intersection(intersect)
      case result
      when Unsatisfiable then # do nothing, it's no longer in the union
      when Nominal then terms.add(result)
      when AntiNominal then anti_terms.add(result)
      when Intersection then intersects.add(result)
      else raise NotImplementedError.new(result.inspect)
      end
    end
    
    Union.build(terms.to_set, anti_terms.to_set, intersects.to_set)
  end
  
  # Return true if this MetaType is a subtype of the other MetaType.
  def <(other); subtype_of?(other) end
  def subtype_of?(other : MetaType)
    self.defns.all? do |defn|
      other.defns.includes?(defn) ||
      other.defns.any? { |d| self.class.is_l_defn_sub_r_defn?(defn, d) }
    end
  end
  
  # A cache of assumptions to prevent mutual recursion when checking subtypes.
  @@defn_subtype_assumes = Set(Tuple(Program::Type, Program::Type)).new
  
  # Return true if the left type satisfies the requirements of the right type.
  def self.is_l_defn_sub_r_defn?(l : Program::Type, r : Program::Type)
    # TODO: for each return false, carry info about why it was false?
    # Maybe we only want to go to the trouble of collecting this info
    # when it is requested by the caller, so as not to slow the base case.
    
    # If these are literally the same type, we can trivially return true.
    return true if r.same? l
    
    # We don't have subtyping of concrete types (i.e. class inheritance),
    # so we know l can't possibly be a subtype of r if r is concrete.
    # Note that by the time we've reached this line, we've already
    # determined that the two types are not identical, so we're only
    # concerned with structural subtyping from here on.
    return false unless r.has_tag?(:abstract)
    
    # TODO: memoize the results of success/failure of the following steps,
    # so we can skip them if we've already done a comparison for l and r.
    # This could also be preserved for use in a selector coloring pass later.
    
    # If we have a standing assumption that l is a subtype of r, return true.
    # Otherwise, move forward with the check and add such an assumption.
    # This is done to prevent infinite recursion in the typechecking.
    # The assumption could turn out to be wrong, but no matter what,
    # we don't gain anything by trying to check something that we're
    # already in the middle of checking some way down the call stack.
    return true if @@defn_subtype_assumes.includes?({l, r})
    @@defn_subtype_assumes.add({l, r})
    
    # A type only matches an interface if all functions match that interface.
    result =
      r.functions.all? do |rf|
        # Hygienic functions are not considered to be real functions for the
        # sake of structural subtyping, so they don't have to be fulfilled.
        next if rf.has_tag?(:hygienic)
        
        # The structural comparison fails if a required method is missing.
        next unless l.has_func?(rf.ident.value)
        lf = l.find_func!(rf.ident.value)
        
        # Just asserting; we expect has_func? and find_func! to prevent this.
        raise "found hygienic function" if lf.has_tag?(:hygienic)
        
        is_l_func_sub_r_func?(l, r, lf, rf)
      end
    
    # Remove our standing assumption about l being a subtype of r -
    # we have our answer and have no more need for this recursion guard.
    @@defn_subtype_assumes.delete({l, r})
    
    result
  end
  
  # Return true if the left func satisfies the requirements of the right func.
  def self.is_l_func_sub_r_func?(
    l : Program::Type, r : Program::Type,
    lf : Program::Function, rf : Program::Function,
  )
    # Get the Infer instance for both l and r functions, to compare them.
    l_infer = Infer.from(l, lf)
    r_infer = Infer.from(r, rf)
    
    # A constructor can only match another constructor, and
    # a constant can only match another constant.
    return false if lf.has_tag?(:constructor) != rf.has_tag?(:constructor)
    return false if lf.has_tag?(:constant) != rf.has_tag?(:constant)
    
    # Must have the same number of parameters.
    return false if lf.param_count != rf.param_count
    
    # TODO: Check receiver rcap (see ponyc subtype.c:240)
    # Covariant receiver rcap for constructors.
    # Contravariant receiver rcap for functions and behaviours.
    
    # Covariant return type.
    return false unless \
      l_infer.resolve(l_infer.ret_tid) < r_infer.resolve(r_infer.ret_tid)
    
    # Contravariant parameter types.
    lf.params.try do |l_params|
      rf.params.try do |r_params|
        l_params.terms.zip(r_params.terms).each do |(l_param, r_param)|
          return false unless \
            r_infer.resolve(r_param) < l_infer.resolve(l_param)
        end
      end
    end
    
    true
  end
  
  def each_reachable_defn : Iterator(Program::Type)
    @inner.each_reachable_defn
  end
  
  def ==(other)
    @inner == other.inner
  end
  
  def hash
    @inner.hash
  end
  
  def show
    "it must be a subtype of #{show_type}"
  end
  
  def show_type
    @inner.inspect
  end
  
  def within_constraints?(list : Iterable(MetaType))
    # TODO: verify total correctness of this algorithm and its use.
    unconstrained = true
    intersected = list.reduce self do |reduction, constraint|
      unconstrained = false
      reduction.intersect(constraint).simplify
    end
    unconstrained || !intersected.unsatisfiable?
  end
end
