struct Savi::Compiler::Infer::MetaType
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
    @inner = Nominal.new(defn).intersect(Capability.new(Cap.from_string(cap)))
  end

  def initialize(defn : ReifiedType, cap : Cap)
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

  def self.cap(cap : Cap)
    MetaType.new(Capability.new(cap))
  end

  def self.cap(name : String)
    MetaType.new(Capability.new(Cap.from_string(name)))
  end

  def cap(cap : Cap)
    MetaType.new(@inner.intersect(Capability.new(cap)))
  end

  def cap(name : String)
    MetaType.new(@inner.intersect(Capability.new(Cap.from_string(name))))
  end

  def cap_only_inner
    inner = @inner
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
  end

  def cap_only
    MetaType.new(cap_only_inner)
  end

  def override_cap(cap : Cap)
    override_cap(Capability.new(cap))
  end

  def override_cap(name : String)
    override_cap(Capability.new(Cap.from_string(name)))
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

  def aliased
    MetaType.new(inner.aliased)
  end

  def consumed
    MetaType.new(inner.consumed)
  end

  def stabilized
    MetaType.new(inner.stabilized)
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

  def with_additional_type_arg!(arg : MetaType) : MetaType
    MetaType.new(inner.with_additional_type_arg!(arg))
  end

  def substitute_type_params_retaining_cap(
    type_params : Array(TypeParam),
    type_args : Array(MetaType)
  ) : MetaType
    return self if type_params.empty?
    MetaType.new(
      inner.substitute_type_params_retaining_cap(type_params, type_args)
    )
  end

  def each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> _)
    @inner.each_type_alias_in_first_layer(&block)
  end

  def substitute_each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> MetaType)
    MetaType.new(@inner.substitute_each_type_alias_in_first_layer(&block))
  end

  def any_type_alias_in_first_layer?
    # TODO: A less hacky approach here would be good.
    each_type_alias_in_first_layer { raise "here's one" }
    false
  rescue
    true
  end

  def is_sendable? : Bool
    inner.is_sendable?
  end

  # A partial reify type param is a type param intersected with a capability.
  def is_partial_reify_of_type_param?(param : TypeParam) : Bool
    inner = inner()
    return false unless inner.is_a?(Intersection)
    return false unless inner.cap
    return false unless inner.anti_terms == nil
    return false unless inner.terms.try(&.size) == 1
    return false unless inner.terms.try(&.first.try(&.defn.==(param)))
    true
  end

  # Returns true if it is safe to refine the type of self to other at runtime.
  # Returns false if doing so would violate capabilities.
  # Returns nil if doing so would be impossible even if we ignored capabilities.
  # TODO: This function isn't actually used by match types - it's only used for
  # Pony runtime trace characteristics, and we're not fully sure it's correct.
  # Needs auditing for correctness in that context, and potential renaming.
  def safe_to_match_as?(ctx : Context, other : MetaType) : Bool?
    inner.safe_to_match_as?(ctx, other.inner)
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

  def cap_only?
    @inner.is_a?(Capability)
  end

  def type_param_only?
    inner = @inner
    inner.is_a?(Nominal) && inner.defn.is_a?(TypeParam)
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
  def single_rt?
    single?.try(&.defn.as(ReifiedType))
  end

  def single!
    raise "not singular: #{show_type}" unless singular?
    single?.not_nil!.defn.as(ReifiedType)
  end

  def single_rt_or_rta!
    single_rt_or_rta?.not_nil!
  end
  def single_rt_or_rta?
    inner = inner()
    case inner
    when Intersection then
      terms = inner.terms
      MetaType.new(terms.first).single_rt_or_rta? if terms && terms.size == 1
    when Nominal then
      defn = inner.defn
      case defn
      when ReifiedTypeAlias; defn
      when ReifiedType; defn
      else nil
      end
    else nil
    end
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
    # TODO: complete the rest of the logic here (think about symmetry)
    removed_terms = Set(Nominal).new
    new_terms = inner.terms.try(&.select do |l|
      # Return Unsatisfiable if any term is a subtype of an anti-term.
      if inner.anti_terms.try(&.any? { |r| l.subtype_of?(ctx, r.negate) })
        return Unsatisfiable.instance
      end

      # Return Unsatisfiable if l is concrete and isn't a subtype of all others.
      # However, type parameter references are exempt from this requirement.
      if l.is_concrete? && inner.terms.try(&.any? { |r|
        !r.defn.is_a?(TypeParam) && !l.subtype_of?(ctx, r)
      })
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
    end.map { |term| simplify_nominal(ctx, term) })

    removed_anti_terms = Set(AntiNominal).new
    new_anti_terms = inner.anti_terms.try(&.select do |l|
      # Remove anti terms that are not subtypes of a term - they are redundant.
      unless inner.terms.try(&.any? do |r|
        r.subtype_of?(ctx, l.negate)
      end)
        removed_anti_terms.add(l)
        next
      end

      true # keep this term
    end)

    # Otherwise, return as a new intersection.
    Intersection.build(inner.cap, new_terms.try(&.to_set), new_anti_terms.try(&.to_set))
  end

  private def self.simplify_union(ctx : Context, inner : Union)
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
    case inner_defn
    when ReifiedType
      return inner if inner_defn.args.empty?
      Nominal.new(ReifiedType.new(inner_defn.link, inner_defn.args.map(&.simplify(ctx))))
    when ReifiedTypeAlias
      return inner if inner_defn.args.empty?
      Nominal.new(ReifiedTypeAlias.new(inner_defn.link, inner_defn.args.map(&.simplify(ctx))))
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

  def map_each_union_member(&block : MetaType -> T) forall T
    results = [] of T

    inner = @inner
    case inner
    when Union
      inner.caps.try(&.each { |cap|
        results << yield MetaType.new(cap)
      })
      inner.terms.try(&.each { |term|
        results << yield MetaType.new(term)
      })
      inner.anti_terms.try(&.each { |anti_term|
        results << yield MetaType.new(anti_term)
      })
      inner.intersects.try(&.each { |intersect|
        results << yield MetaType.new(intersect)
      })
    when Intersection; results << yield MetaType.new(inner)
    when Nominal;      results << yield MetaType.new(inner)
    when Capability;   results << yield MetaType.new(inner)
    else NotImplementedError.new("map_each_union_member for #{inner.inspect}")
    end

    results
  end

  def map_each_intersection_term_and_or_cap(&block : MetaType -> T) forall T
    results = [] of T

    inner = @inner
    case inner
    when Union
      raise "wrap a call to map_each_union_member around this method first"
    when Intersection
      cap = MetaType.new(inner.cap || Unconstrained.instance)
      inner.terms.try(&.each { |term|
        results << yield MetaType.new(term).intersect(cap)
      })
    when Nominal; results << yield MetaType.new(inner)
    when Capability; results << yield MetaType.new(inner)
    else NotImplementedError.new("each_intersection_term_and_or_cap for #{inner.inspect}")
    end

    results
  end

  def gather_call_receiver_span(
    ctx : Context,
    pos : Source::Pos,
    infer : Visitor?,
    name : String
  ) : Span
    @inner.gather_call_receiver_span(ctx, pos, infer, name)
  end

  def find_callable_func_defns(
    ctx : Context,
    name : String,
  ) : Set(Tuple(MetaType, ReifiedType?, Program::Function?))
    set = Set(Tuple(MetaType, ReifiedType?, Program::Function?)).new
    @inner.find_callable_func_defns(ctx, name).try(&.each { |tuple|
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
