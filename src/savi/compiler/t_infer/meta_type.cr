struct Savi::Compiler::TInfer::MetaType
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

  def initialize(defn : ReifiedType)
    @inner = Nominal.new(defn)
  end

  def initialize(defn : ReifiedType)
    @inner = Nominal.new(defn)
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

  def type_params : Set(TypeParam)
    inner.type_params
  end

  def with_additional_type_arg!(arg : MetaType) : MetaType
    MetaType.new(inner.with_additional_type_arg!(arg))
  end

  def substitute_type_params(
    type_params : Array(TypeParam),
    type_args : Array(MetaType)
  ) : MetaType
    return self if type_params.empty?
    MetaType.new(inner.substitute_type_params(type_params, type_args))
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
    Intersection.build(new_terms.try(&.to_set), new_anti_terms.try(&.to_set))
  end

  private def self.simplify_union(ctx : Context, inner : Union)
    terms = Set(Nominal).new
    anti_terms = Set(AntiNominal).new
    intersects = Set(Intersection).new

    # Just copy the terms and anti-terms without working with them.
    # TODO: are there any simplifications we can/should apply here?
    # TODO: consider some that are in symmetry with those for intersections.
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

    Union.build(terms.to_set, anti_terms.to_set, intersects.to_set)
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

  def map_each_union_member(&block : MetaType -> T) forall T
    results = [] of T

    inner = @inner
    case inner
    when Union
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
    else NotImplementedError.new("map_each_union_member for #{inner.inspect}")
    end

    results
  end

  def map_each_intersection_term(&block : MetaType -> T) forall T
    results = [] of T

    inner = @inner
    case inner
    when Union
      raise "wrap a call to map_each_union_member around this method first"
    when Intersection
      inner.terms.try(&.each { |term| results << yield MetaType.new(term) })
    when Nominal; results << yield MetaType.new(inner)
    else NotImplementedError.new("each_intersection_term for #{inner.inspect}")
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
end
