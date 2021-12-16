struct Savi::Compiler::TInfer::MetaType::Union
  getter terms : Set(Nominal)?
  getter anti_terms : Set(AntiNominal)?
  getter intersects : Set(Intersection)?

  def initialize(@terms = nil, @anti_terms = nil, @intersects = nil)
    count = 0
    count += terms.try(&.size) || 0
    count += anti_terms.try(&.size) || 0
    count += intersects.try(&.size) || 0

    raise "too few terms: #{inspect}" if count <= 1

    raise "empty terms" if terms && terms.try(&.empty?)
    raise "empty anti_terms" if anti_terms && anti_terms.try(&.empty?)
    raise "empty intersects" if intersects && intersects.try(&.empty?)
  end

  def all_terms
    all_terms = [] of Inner
    terms.try(&.each { |term| all_terms << term })
    anti_terms.try(&.each { |anti_term| all_terms << anti_term })
    intersects.try(&.each { |intersect| all_terms << intersect })
    all_terms
  end

  # This function works like .new, but it accounts for cases where there
  # aren't enough terms, anti-terms, and intersections to build a real Union.
  # Returns Unsatisfiable if no terms or anti-terms are supplied.
  def self.build(
    terms : Set(Nominal)? = nil,
    anti_terms : Set(AntiNominal)? = nil,
    intersects : Set(Intersection)? = nil,
  ) : Inner
    count = 0
    count += terms.try(&.size) || 0
    count += anti_terms.try(&.size) || 0
    count += intersects.try(&.size) || 0

    case count
    when 0 then Unsatisfiable.instance
    when 1 then terms.try(&.first?) || anti_terms.try(&.first?) || \
                intersects.not_nil!.first
    else
      terms = nil if terms && terms.empty?
      anti_terms = nil if anti_terms && anti_terms.empty?
      intersects = nil if intersects && intersects.empty?
      new(terms, anti_terms, intersects)
    end
  end

  def inspect(io : IO)
    first = true
    io << "("

    intersects.not_nil!.each do |intersect|
      io << " | " unless first; first = false
      intersect.inspect(io)
    end if intersects

    anti_terms.not_nil!.each do |anti_term|
      io << " | " unless first; first = false
      anti_term.inspect(io)
    end if anti_terms

    terms.not_nil!.each do |term|
      io << " | " unless first; first = false
      term.inspect(io)
    end if terms

    io << ")"
  end

  def each_reachable_defn(ctx : Context) : Array(ReifiedType)
    defns = [] of ReifiedType

    defns += terms.not_nil!.map(&.each_reachable_defn(ctx)).flatten if terms
    defns += intersects.not_nil!.map(&.each_reachable_defn(ctx)).flatten if intersects

    defns
  end

  def gather_call_receiver_span(
    ctx : Context,
    pos : Source::Pos,
    infer : Visitor?,
    name : String
  ) : Span
    span = Span.simple(MetaType.unsatisfiable)

    terms.try { |terms|
      span = span.reduce_combine_mts(
        terms.map(&.gather_call_receiver_span(ctx, pos, infer, name))
      ) { |accum, mt| accum.unite(mt) }
    }

    intersects.try { |intersects|
      span = span.reduce_combine_mts(
        intersects.map(&.gather_call_receiver_span(ctx, pos, infer, name))
      ) { |accum, mt| accum.unite(mt) }
    }

    if span.any_mt?(&.unsatisfiable?)
      return Span.error(pos,
        "The '#{name}' member can't be reached on this receiver", [
          {pos, "the type #{self.inspect} has no types defining that member"}
        ]
      )
    end

    span
  end

  def find_callable_func_defns(ctx, name : String)
    list = [] of Tuple(MetaType, ReifiedType?, Program::Function?)

    # Every nominal in the union must have an implementation of the call.
    # If it doesn't, we will collect it here as a failure to find it.
    terms.not_nil!.each do |term|
      defn = term.defn
      result = term.find_callable_func_defns(ctx, name)
      result ||= [{MetaType.new(term), (defn if defn.is_a?(ReifiedType)), nil}]
      list.concat(result)
    end if terms

    # Every intersection must have one or more implementations of the call.
    # Otherwise, it will return some error infomration in its list for us.
    intersects.not_nil!.each do |intersect|
      result = intersect.find_callable_func_defns(ctx, name).not_nil!
      list.concat(result)
    end if intersects

    list
  end

  def any_callable_func_defn_type(ctx, name : String) : ReifiedType?
    # Return the first nominal or intersection in this union that has this func.
    terms.try(&.each do |term|
      term.any_callable_func_defn_type(ctx, name).try do |result|
        return result
      end
    end)
    intersects.try(&.each do |intersect|
      intersect.any_callable_func_defn_type(ctx, name).try do |result|
        return result
      end
    end)

    nil
  end

  def negate : Inner
    # De Morgan's Law:
    # The negation of a union is the intersection of negations of its terms.
    result = nil
    terms.not_nil!.each do |term|
      term = term.negate
      result = result ? result.intersect(term) : term
      return result if result.is_a?(Unsatisfiable)
    end if terms
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

  def intersect(
    other : (Nominal | AntiNominal | Intersection | Union)
  )
    # Intersect the other with each term that we contain in the union,
    # discarding any results that come back as Unsatisfiable intersections.
    results = [] of Inner
    terms.not_nil!.each do |term|
      result = other.intersect(term)
      results << result unless result.is_a?(Unsatisfiable)
    end if terms
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
    return self if terms && terms.not_nil!.includes?(other)

    # Unconstrained if we have already have an anti-term for this type.
    return Unconstrained.instance \
      if anti_terms && anti_terms.not_nil!.includes?(AntiNominal.new(other.defn))

    # Otherwise, create a new union that adds this type.
    new_terms =
      if terms
        terms.not_nil!.dup.add(other)
      else
        [other].to_set
      end
    Union.new(new_terms, anti_terms, intersects)
  end

  def unite(other : AntiNominal)
    # No change if we've already united with this anti-type.
    return self if anti_terms && anti_terms.not_nil!.includes?(other)

    # Unconstrained if we have already have a term for this anti-type.
    return Unconstrained.instance \
      if terms && terms.not_nil!.includes?(Nominal.new(other.defn))

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
    other.terms.not_nil!.each do |term|
      result = result.unite(term)
      return result if result.is_a?(Unconstrained)
    end if other.terms
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

  def type_params
    result = Set(TypeParam).new

    terms.not_nil!.each do |term|
      result.concat(term.type_params)
    end if terms
    anti_terms.not_nil!.each do |anti_term|
      result.concat(anti_term.type_params)
    end if anti_terms
    intersects.not_nil!.each do |intersect|
      result.concat(intersect.type_params)
    end if intersects

    result
  end

  def with_additional_type_arg!(arg : MetaType) : Inner
    raise NotImplementedError.new("#{self} with_additional_type_arg!")
  end

  def substitute_type_params(
    type_params : Array(TypeParam),
    type_args : Array(MetaType)
  ) : Inner
    result = Unsatisfiable.instance

    terms.try(&.each { |term|
      result = result.unite(
        term.substitute_type_params(type_params, type_args)
      )
    })

    anti_terms.try(&.each { |anti_term|
      result = result.unite(
        anti_term.substitute_type_params(type_params, type_args)
      )
    })

    intersects.try(&.each { |intersect|
      result = result.unite(
        intersect.substitute_type_params(type_params, type_args)
      )
    })

    result
  end

  def each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> _)
    terms.try(&.each(&.each_type_alias_in_first_layer(&block)))
    anti_terms.try(&.each(&.each_type_alias_in_first_layer(&block)))
    intersects.try(&.each(&.each_type_alias_in_first_layer(&block)))
  end

  def substitute_each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> MetaType) : Inner
    result = Unsatisfiable.instance

    terms.try(&.each { |term|
      result = result.unite(term.substitute_each_type_alias_in_first_layer(&block))
    })

    anti_terms.try(&.each { |anti_term|
      result = result.unite(anti_term.substitute_each_type_alias_in_first_layer(&block))
    })

    intersects.try(&.each { |intersect|
      result = result.unite(intersect.substitute_each_type_alias_in_first_layer(&block))
    })

    result
  end

  def subtype_of?(ctx : Context, other : (Nominal | AntiNominal | Intersection)) : Bool
    # This union is a subtype of the other if and only if
    # all terms in the union are subtypes of that other.
    result = true
    result &&= terms.not_nil!.all?(&.subtype_of?(ctx, other)) if terms
    result &&= anti_terms.not_nil!.all?(&.subtype_of?(ctx, other)) if anti_terms
    result &&= intersects.not_nil!.all?(&.subtype_of?(ctx, other)) if intersects
    result
  end

  def supertype_of?(ctx : Context, other : (Nominal | AntiNominal | Intersection)) : Bool
    # This union is a supertype of the given other if and only if
    # any term in the union qualifies as a supertype of that other.
    result = false
    result ||= terms.not_nil!.any?(&.supertype_of?(ctx, other)) if terms
    result ||= anti_terms.not_nil!.any?(&.supertype_of?(ctx, other)) if anti_terms
    result ||= intersects.not_nil!.any?(&.supertype_of?(ctx, other)) if intersects
    result
  end

  def subtype_of?(ctx : Context, other : Union) : Bool
    # This union is a subtype of the given other union if and only if
    # all terms in the union are subtypes of that other.
    result = true
    result &&= terms.not_nil!.all?(&.subtype_of?(ctx, other)) if terms
    result &&= anti_terms.not_nil!.all?(&.subtype_of?(ctx, other)) if anti_terms
    result &&= intersects.not_nil!.all?(&.subtype_of?(ctx, other)) if intersects
    result
  end

  def supertype_of?(ctx : Context, other : Union) : Bool
    other.subtype_of?(ctx, self) # delegate to the other function via symmetry
  end

  def subtype_of?(ctx : Context, other : (Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def supertype_of?(ctx : Context, other : (Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def satisfies_bound?(ctx : Context, bound) : Bool
    # This union satisfies the given bound if and only if
    # all terms in the union satisfy the bound.
    result = true
    result &&= terms.not_nil!.all?(&.satisfies_bound?(ctx, bound)) if terms
    result &&= anti_terms.not_nil!.all?(&.satisfies_bound?(ctx, bound)) if anti_terms
    result &&= intersects.not_nil!.all?(&.satisfies_bound?(ctx, bound)) if intersects
    result
  end
end
