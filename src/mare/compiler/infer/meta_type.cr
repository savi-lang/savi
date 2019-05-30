struct Mare::Compiler::Infer::MetaType
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
  struct Capability;   end # A reference capability.
  class Unsatisfiable; end # It's impossible to find a type that fulfills this.
  class Unconstrained; end # All types fulfill this - totally unconstrained.
  
  alias Inner = (
    Union | Intersection | AntiNominal | Nominal | Capability |
    Unsatisfiable | Unconstrained)
  
  getter inner : Inner
  
  def initialize(@inner)
  end
  
  def initialize(defn : Infer::ReifiedType, cap : String? = nil)
    cap ||= defn.defn.cap.value
    @inner = Nominal.new(defn).intersect(Capability.new(cap))
  end
  
  def self.new_nominal(defn : Infer::ReifiedType)
    MetaType.new(Nominal.new(defn))
  end
  
  def self.new_type_param(defn : Refer::DeclParam)
    MetaType.new(Nominal.new(defn))
  end
  
  def self.new_union(types : Iterable(MetaType))
    inner = Unsatisfiable.instance
    types.each { |mt| inner = inner.unite(mt.inner) }
    MetaType.new(inner)
  end
  
  def self.new_intersection(types : Iterable(MetaType))
    inner = Unconstrained.instance
    types.each { |mt| inner = inner.intersect(mt.inner) }
    MetaType.new(inner)
  end
  
  def self.cap(name : String)
    MetaType.new(Capability.new(name))
  end
  
  def cap(name : String)
    MetaType.new(@inner.intersect(Capability.new(name)))
  end
  
  def cap_only
    inner = @inner
    MetaType.new(
      case inner
      when Capability; inner
      when Union; caps = inner.caps; caps && caps.size == 1 && caps.first
      when Intersection; inner.cap
      end.as(Capability)
    )
  end
  
  def cap_only_name
    inner = @inner
    case inner
    when Capability; inner
    when Union; caps = inner.caps; caps && caps.size == 1 && caps.first
    when Intersection; inner.cap
    end.as(Capability).name
  end
  
  def override_cap(name : String)
    override_cap(Capability.new(name))
  end
  
  def override_cap(meta_type : MetaType)
    override_cap(meta_type.inner.as(Capability))
  end
  
  def override_cap(cap : Capability)
    inner = @inner
    MetaType.new(
      case inner
      when Nominal
        inner.intersect(cap)
      when Intersection
        Intersection.new(cap, inner.terms, inner.anti_terms)
      else
        raise NotImplementedError.new(inner.inspect)
      end
    )
  end
  
  def ephemeralize
    MetaType.new(inner.ephemeralize)
  end
  
  def strip_ephemeral
    MetaType.new(inner.strip_ephemeral)
  end
  
  def alias
    MetaType.new(inner.alias)
  end
  
  def is_sendable? : Bool
    inner.is_sendable?
  end
  
  def viewed_from(origin : MetaType)
    origin_inner = origin.inner
    case origin_inner
    when Capability
      MetaType.new(inner.viewed_from(origin_inner))
    when Intersection
      MetaType.new(inner.viewed_from(origin_inner.cap.not_nil!)) # TODO: convert to_generic
    else
      raise NotImplementedError.new("#{origin_inner.inspect}->#{inner.inspect}")
    end
  end
  
  def extracted_from(origin : MetaType)
    origin_inner = origin.inner
    case origin_inner
    when Capability
      MetaType.new(inner.extracted_from(origin_inner))
    when Intersection
      MetaType.new(inner.extracted_from(origin_inner.cap.not_nil!)) # TODO: convert to_generic
    else
      raise NotImplementedError.new("#{origin_inner.inspect}+>#{inner.inspect}")
    end
  end
  
  def cap_only?
    @inner.is_a?(Capability)
  end
  
  def within_constraints?(infer : Infer, types : Iterable(MetaType))
    infer.is_subtype?(self, self.class.new_intersection(types))
  end
  
  def unsatisfiable?
    @inner.is_a?(Unsatisfiable)
  end
  
  def singular?
    !!single?
  end
  
  def single? : Nominal?
    inner = @inner
    case inner
    when Nominal then inner
    when Intersection then inner.terms.try(&.first?)
    else nil
    end
  end
  
  def single!
    raise "not singular: #{show_type}" unless singular?
    single?.not_nil!.defn.as(Infer::ReifiedType)
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
  
  def simplify(infer : Infer)
    inner = @inner
    
    # Currently we only have the logic to simplify these cases:
    return MetaType.new(simplify_union(infer, inner)) if inner.is_a?(Union) && inner.intersects
    return MetaType.new(simplify_intersection(infer, inner)) if inner.is_a?(Intersection)
    
    self
  end
  
  private def simplify_intersection(infer : Infer, inner : Intersection)
    # TODO: complete the rest of the logic here (think about symmetry)
    removed_terms = Set(Nominal).new
    new_terms = inner.terms.try(&.select do |l|
      # Return Unsatisfiable if any term is a subtype of an anti-term.
      if inner.anti_terms.try(&.any? { |r| infer.is_subtype?(l.defn, r.defn) })
        return Unsatisfiable.instance
      end
      
      # Return Unsatisfiable if l is concrete and isn't a subtype of all others.
      if l.is_concrete? && inner.terms.try(&.any? { |r| !infer.is_subtype?(l.defn, r.defn) })
        return Unsatisfiable.instance
      end
      
      # Remove terms that are supertypes of another term - they are redundant.
      if inner.terms.try(&.any? do |r|
        l != r && !removed_terms.includes?(r) && infer.is_subtype?(r.defn, l.defn)
      end)
        removed_terms.add(l)
        next
      end
      
      true # keep this term
    end)
    
    # If we didn't remove anything, there was no change.
    return inner if removed_terms.empty?
    
    # Otherwise, return as a new intersection.
    Intersection.build(inner.cap, new_terms.try(&.to_set), inner.anti_terms)
  end
  
  private def simplify_union(infer : Infer, inner : Union)
    caps = Set(Capability).new
    terms = Set(Nominal).new
    anti_terms = Set(AntiNominal).new
    intersects = Set(Intersection).new
    
    # Just copy the terms and anti-terms without working with them.
    # TODO: are there any simplifications we can/should apply here?
    # TODO: consider some that are in symmetry with those for intersections.
    caps.concat(inner.caps.not_nil!) if inner.caps
    terms.concat(inner.terms.not_nil!) if inner.terms
    anti_terms.concat(inner.anti_terms.not_nil!) if inner.anti_terms
    
    # Simplify each intersection, collecting the results.
    inner.intersects.not_nil!.each do |intersect|
      result = simplify_intersection(infer, intersect)
      case result
      when Unsatisfiable then # do nothing, it's no longer in the union
      when Nominal then terms.add(result)
      when AntiNominal then anti_terms.add(result)
      when Intersection then intersects.add(result)
      else raise NotImplementedError.new(result.inspect)
      end
    end
    
    Union.build(caps.to_set, terms.to_set, anti_terms.to_set, intersects.to_set)
  end
  
  # Return true if this MetaType is a subtype of the other MetaType.
  def subtype_of?(infer : Infer, other : MetaType)
    inner.subtype_of?(infer, other.inner)
  end
  
  def each_reachable_defn : Iterator(Infer::ReifiedType)
    @inner.each_reachable_defn
  end
  
  def find_callable_func_defns(
    infer : Infer,
    name : String,
  ) : Set(Tuple(Inner, Infer::ReifiedType?, Program::Function?))
    set = Set(Tuple(Inner, Infer::ReifiedType?, Program::Function?)).new
    @inner.find_callable_func_defns(infer, name).try(&.each { |tuple|
      set.add(tuple)
    })
    set
  end
  
  def any_callable_func_defn_type(name : String) : Infer::ReifiedType?
    @inner.any_callable_func_defn_type(name)
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
