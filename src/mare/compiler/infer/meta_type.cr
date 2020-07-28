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

  def initialize(defn : ReifiedType, cap : String? = nil)
    cap ||= defn.link.cap
    @inner = Nominal.new(defn).intersect(Capability.new(cap))
  end

  def initialize(defn : ReifiedTypeAlias)
    @inner = Nominal.new(defn)
  end

  def self.new_nominal(defn : ReifiedType)
    MetaType.new(Nominal.new(defn))
  end

  def self.new_alias(defn : ReifiedTypeAlias)
    MetaType.new(Nominal.new(defn))
  end

  def self.new_type_param(defn : TypeParam)
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

  def self.unsatisfiable
    MetaType.new(Unsatisfiable.instance)
  end

  def self.unconstrained
    MetaType.new(Unconstrained.instance)
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
      when Nominal; Capability::NON if inner.ignores_cap?
      when Intersection
        inner.cap || (inner.ignores_cap? ? Capability::NON : nil)
      when Union
        caps = Set(Capability).new
        inner.caps.try(&.each { |cap| caps << cap })
        inner.intersects.try(&.each { |intersect|
          cap = intersect.cap
          caps << cap if cap
        })
        caps.size == 1 && caps.first
      else
        nil
      end.as(Capability)
    )
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
      when Capability
        cap
      when Nominal
        inner.intersect(cap)
      when Intersection
        Intersection.new(cap, inner.terms, inner.anti_terms)
      when Unsatisfiable
        Unsatisfiable.instance
      when Unconstrained
        cap
      when Union
        result = Unsatisfiable.instance
        inner.caps.try(&.each {
          result = result.unite(cap)
        })
        inner.terms.try(&.each { |term|
          result = result.unite(term.intersect(cap))
        })
        inner.anti_terms.try(&.each { |anti_term|
          result = result.unite(anti_term.intersect(cap))
        })
        inner.intersects.try(&.each { |intersect|
          result = result.unite(
            Intersection.new(cap, intersect.terms, intersect.anti_terms)
          )
        })
        result
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

  def strip_cap
    MetaType.new(inner.strip_cap)
  end

  def partial_reifications
    inner.partial_reifications.map { |i| MetaType.new(i) }
  end

  def type_params : Set(TypeParam)
    inner.type_params
  end

  def substitute_type_params(substitutions : Hash(TypeParam, MetaType))
    MetaType.new(inner.substitute_type_params(substitutions))
  end

  def is_sendable? : Bool
    inner.is_sendable?
  end

  # A partial reify type param is a type param intersected with a capability.
  def is_partial_reify_type_param? : Bool
    inner = inner()
    return false unless inner.is_a?(Intersection)
    return false unless inner.cap
    return false unless inner.anti_terms == nil
    return false unless inner.terms.try(&.size) == 1
    return false unless inner.terms.try(&.first.try(&.defn.is_a?(TypeParam)))
    true
  end

  # Returns true if it is safe to refine the type of self to other at runtime.
  # Returns false if doing so would violate capabilities.
  # Returns nil if doing so would be impossible even if we ignored capabilities.
  def safe_to_match_as?(ctx : Context, other : MetaType) : Bool?
    inner.safe_to_match_as?(ctx, other.inner)
  end

  def recovered
    MetaType.new(inner.recovered)
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
      raise NotImplementedError.new("#{origin_inner.inspect}->>#{inner.inspect}")
    end
  end

  def cap_only?
    @inner.is_a?(Capability)
  end

  def within_constraints?(ctx : Context, types : Iterable(MetaType))
    subtype_of?(ctx, self.class.new_intersection(types))
  end

  def unsatisfiable?
    @inner.is_a?(Unsatisfiable)
  end

  def unconstrained?
    @inner.is_a?(Unconstrained)
  end

  def singular?
    !!single?
  end

  def single? : Nominal?
    inner = @inner
    nominal =
      case inner
      when Nominal then inner
      when Intersection then
        terms = inner.terms
        if terms
          terms.find { |t| defn = t.defn; defn.is_a?(ReifiedType) && defn.link.is_concrete? } \
          || terms.find { |t| t.defn.is_a?(ReifiedType) } \
          || terms.first
        end
      else nil
      end
    nominal if nominal && nominal.defn.is_a?(ReifiedType)
  end

  def single!
    raise "not singular: #{show_type}" unless singular?
    single?.not_nil!.defn.as(ReifiedType)
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

  def simplify(ctx : Context) : MetaType
    MetaType.new(MetaType.simplify_inner(ctx, @inner))
  end

  protected def self.simplify_inner(ctx : Context, inner : Inner) : Inner
    # Currently we only have the logic to simplify these cases:
    return simplify_union(ctx, inner) if inner.is_a?(Union)
    return simplify_intersection(ctx, inner) if inner.is_a?(Intersection)
    return simplify_nominal(ctx, inner) if inner.is_a?(Nominal)
    inner
  end

  private def self.simplify_intersection(ctx : Context, inner : Intersection)
    # If we have any reified type aliases, we need to settle those first
    # by unwrapping them, intersecting them, and recursively calling simplify.
    if inner.terms.try(&.any?(&.defn.is_a?(ReifiedTypeAlias)))
      result = Unconstrained.instance

      # Intersect all of the pieces of this intersection, which would normally
      # build up the same intersection again but for the unwrapping of the
      # type aliases we find within, some of which may even be Unions
      # (which would cause the resulting "intersection" to become a Union too).
      inner.cap.try do |cap|
        result = result.intersect(cap)
        return result if result.is_a?(Unsatisfiable)
      end
      inner.terms.not_nil!.each do |term|
        # Here is where we deal with the special case of unwrapping aliases:
        begin
          term_defn = term.defn
          term = ctx.infer.unwrap_alias(ctx, term_defn).inner if term_defn.is_a?(ReifiedTypeAlias)
        end
        result = result.intersect(term)
        return result if result.is_a?(Unsatisfiable)
      end if inner.terms
      inner.anti_terms.not_nil!.each do |term|
        result = result.intersect(term)
        return result if result.is_a?(Unsatisfiable)
      end if inner.anti_terms

      # Return the fully intersected result, simplified again via recursion.
      # We stop recursing this code path when we see no more aliases to unwrap.
      return simplify_inner(ctx, result)
    end

    # TODO: complete the rest of the logic here (think about symmetry)
    removed_terms = Set(Nominal).new
    new_terms = inner.terms.try(&.select do |l|
      # Return Unsatisfiable if any term is a subtype of an anti-term.
      if inner.anti_terms.try(&.any? { |r| l.subtype_of?(ctx, r) })
        return Unsatisfiable.instance
      end

      # Return Unsatisfiable if l is concrete and isn't a subtype of all others.
      if l.is_concrete? && inner.terms.try(&.any? { |r| !l.subtype_of?(ctx, r) })
        return Unsatisfiable.instance
      end

      # Remove terms that are supertypes of another term - they are redundant.
      if inner.terms.try(&.any? do |r|
        l != r && !removed_terms.includes?(r) && r.subtype_of?(ctx, l)
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

  private def self.simplify_union(ctx : Context, inner : Union)
    # If we have any reified type aliases, we need to settle those first
    # by unwrapping them, intersecting them, and recursively calling simplify.
    if inner.terms.try(&.any?(&.defn.is_a?(ReifiedTypeAlias))) \
    || inner.intersects.try(&.any?(&.terms.try(&.any?(&.defn.is_a?(ReifiedTypeAlias)))))
      result = Unsatisfiable.instance

      # Unite all of the pieces of this union, which would normally build up the
      # same union again but for the unwrapping of the type aliases we find.
      inner.caps.not_nil!.each do |cap|
        result = result.unite(cap)
        return result if result.is_a?(Unconstrained)
      end if inner.caps
      inner.terms.not_nil!.each do |term|
        # Here is where we deal with the special case of unwrapping aliases:
        begin
          term_defn = term.defn
          term = ctx.infer.unwrap_alias(ctx, term_defn).inner if term_defn.is_a?(ReifiedTypeAlias)
        end
        result = result.unite(term)
        return result if result.is_a?(Unconstrained)
      end if inner.terms
      inner.anti_terms.not_nil!.each do |term|
        result = result.unite(term)
        return result if result.is_a?(Unconstrained)
      end if inner.anti_terms
      inner.intersects.not_nil!.each do |intersect|
        # Here is where we deal with the special case of unwrapping aliases:
        if intersect.terms.try(&.any?(&.defn.is_a?(ReifiedTypeAlias)))
          result = result.unite(simplify_inner(ctx, intersect))
        else
          result = result.unite(intersect)
        end
        return result if result.is_a?(Unconstrained)
      end if inner.intersects

      # Return the fully intersected result, simplified again via recursion.
      # We stop recursing this code path when we see no more aliases to unwrap.
      return simplify_inner(ctx, result)
    end

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
      result = simplify_intersection(ctx, intersect)
      case result
      when Unsatisfiable then # do nothing, it's no longer in the union
      when Nominal then terms.add(result)
      when AntiNominal then anti_terms.add(result)
      when Intersection then intersects.add(result)
      else raise NotImplementedError.new(result.inspect)
      end
    end if inner.intersects

    Union.build(caps.to_set, terms.to_set, anti_terms.to_set, intersects.to_set)
  end

  private def self.simplify_nominal(ctx : Context, inner : Nominal)
    inner_defn = inner.defn
    if inner_defn.is_a?(ReifiedTypeAlias)
      simplify_inner(ctx, ctx.infer.unwrap_alias(ctx, inner_defn).inner)
    else
      inner
    end
  end

  # Return true if this MetaType is a subtype of the other MetaType.
  def subtype_of?(ctx : Context, other : MetaType)
    inner.subtype_of?(ctx, other.inner)
  end

  # Return true if this MetaType is a satisfies the other MetaType
  # as a type parameter bound/constraint.
  def satisfies_bound?(ctx : Context, other : MetaType)
    inner.satisfies_bound?(ctx, other.inner)
  end

  def each_reachable_defn(ctx : Context) : Array(ReifiedType)
    @inner.each_reachable_defn(ctx)
  end

  def each_reachable_defn_with_cap(ctx : Context) : Array({ReifiedType, Capability})
    results = [] of {ReifiedType, Capability}

    inner = @inner
    intersects =
      case inner
      when Intersection; [inner]
      when Union; inner.intersects
      else return results
      end

    intersects.not_nil!.each do |intersect|
      cap = intersect.cap
      next unless cap

      intersect.each_reachable_defn(ctx).each do |defn|
        results << {defn, cap}
      end
    end

    results
  end

  def find_callable_func_defns(
    ctx : Context,
    infer : ForReifiedFunc,
    name : String,
  ) : Set(Tuple(Inner, ReifiedType?, Program::Function?))
    set = Set(Tuple(Inner, ReifiedType?, Program::Function?)).new
    @inner.find_callable_func_defns(ctx, infer, name).try(&.each { |tuple|
      set.add(tuple)
    })
    set
  end

  def any_callable_func_defn_type(ctx, name : String) : ReifiedType?
    @inner.any_callable_func_defn_type(ctx, name)
  end

  def show_type
    @inner.inspect
  end

  def cap_value
    @inner.as(Capability).value
  end
end
