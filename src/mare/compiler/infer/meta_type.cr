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
  
  def self.new_intersection(types : Iterable(MetaType))
    inner = Unbounded.instance
    types.each { |mt| inner = inner.intersect(mt.inner) }
    MetaType.new(inner)
  end
  
  def within_constraints?(types : Iterable(MetaType))
    inner = @inner
    types.each { |mt| inner = inner.intersect(mt.inner) }
    !MetaType.new(inner).simplify.unsatisfiable?
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
      if inner.anti_terms.try(&.any? { |r| l.defn < r.defn })
        return Unsatisfiable.instance
      end
      
      # Return Unsatisfiable if l is concrete and isn't a subtype of all others.
      if l.is_concrete? && !inner.terms.all? { |r| l.defn < r.defn }
        return Unsatisfiable.instance
      end
      
      # Remove terms that are supertypes of another term - they are redundant.
      if inner.terms.any? do |r|
        l != r && !removed_terms.includes?(r) && r.defn < l.defn
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
    inner.subtype_of?(other.inner)
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
end
