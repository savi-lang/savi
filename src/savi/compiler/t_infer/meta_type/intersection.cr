struct Savi::Compiler::TInfer::MetaType::Intersection
  getter terms : Set(Nominal)?
  getter anti_terms : Set(AntiNominal)?

  def initialize(@terms = nil, @anti_terms = nil)
    count = 0
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
    terms : Set(Nominal)? = nil,
    anti_terms : Set(AntiNominal)? = nil,
  ) : Inner
    count = 0
    count += terms.try(&.size) || 0
    count += anti_terms.try(&.size) || 0

    case count
    when 0 then Unconstrained.instance
    when 1
      terms.try(&.first?) || anti_terms.not_nil!.first
    else
      terms = nil if terms && terms.empty?
      anti_terms = nil if anti_terms && anti_terms.empty?
      new(terms, anti_terms)
    end
  end

  def inspect(io : IO)
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

    io << ")"
  end

  def each_reachable_defn(ctx : Context) : Array(ReifiedType)
    iter = ([] of ReifiedType)

    iter += terms.not_nil!.map(&.each_reachable_defn(ctx)).flatten if terms

    iter
  end

  def gather_call_receiver_span(
    ctx : Context,
    pos : Source::Pos,
    infer : Visitor?,
    name : String
  ) : Span
    span = Span.simple(MetaType.new(Unconstrained.instance))

    terms.try { |terms|
      term_spans = terms.map(&.gather_call_receiver_span(ctx, pos, infer, name))
      term_spans_no_errors = term_spans.reject(&.any_error?)
      term_spans = term_spans_no_errors unless term_spans_no_errors.empty?
      span = span
        .reduce_combine_mts(term_spans) { |accum, mt| accum.intersect(mt) }
    }

    if span.any_mt?(&.unconstrained?)
      return Span.error(pos,
        "The '#{name}' function can't be called on this receiver", [
          {pos, "the type #{self.inspect} has no types defining that function"}
        ]
      )
    end

    span
  end

  def find_callable_func_defns(ctx, name : String)
    list = [] of Tuple(MetaType, ReifiedType?, Program::Function?)

    # Collect a result for nominal in this intersection that has this func.
    terms.try(&.each do |term|
      term.find_callable_func_defns(ctx, name).try do |result|
        result.each do |_, defn, func|
          # Replace the inner term with an inner of this intersection.
          # This will be used for subtype checking later, and we want to
          # make sure that our cap will be taken into account, if any.
          # TODO: Can this be removed now that we are ignoring caps?
          list << {MetaType.new(self), defn, func}
        end
      end
    end)

    # If none of the nominals in this intersection had the func,
    # we're in trouble; collect the list of types that failed our search.
    if list.empty?
      terms.try(&.each do |term|
        defn = term.defn
        list << {MetaType.new(self), (defn if defn.is_a?(ReifiedType)), nil}
      end)
    end

    # If for some reason we're still empty (like in the case of an
    # intersection of anti-nominals), we have to return nil.
    list << {MetaType.new(self), nil, nil} if list.empty?

    list
  end

  def any_callable_func_defn_type(ctx, name : String) : ReifiedType?
    # Return the first nominal in this intersection that has this func.
    terms.try(&.each do |term|
      term.any_callable_func_defn_type(ctx, name).try do |result|
        return result
      end
    end)

    nil
  end

  def negate : Inner
    # De Morgan's Law:
    # The negation of an intersection is the union of negations of its terms.

    new_terms = anti_terms.try(&.map(&.negate).to_set) || Set(Nominal).new
    new_anti_terms = terms.try(&.map(&.negate).to_set) || Set(AntiNominal).new
    new_terms = nil if new_terms.empty?
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
    Intersection.new(new_terms, anti_terms)
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
    Intersection.new(terms, new_anti_terms)
  end

  def intersect(other : Intersection)
    # Intersect each individual term of other into this running intersection.
    # If the result becomes Unsatisfiable, return so immediately.
    result = self
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

  def unite(other : Nominal)
    Union.new([other].to_set, nil, [self].to_set)
  end

  def unite(other : AntiNominal)
    Union.new(nil, [other].to_set, [self].to_set)
  end

  def unite(other : Intersection)
    return self if self == other

    Union.new(nil, nil, [self, other].to_set)
  end

  def unite(other : Union)
    other.unite(self) # delegate to the "higher" class via commutativity
  end

  def type_params
    result = Set(TypeParam).new

    terms.not_nil!.each do |term|
      result.concat(term.type_params)
    end if terms
    anti_terms.not_nil!.each do |anti_term|
      result.concat(anti_term.type_params)
    end if anti_terms

    result
  end

  def with_additional_type_arg!(arg : MetaType) : Inner
    terms = terms()
    raise NotImplementedError.new("#{self} with_additional_type_arg!") \
      unless terms && terms.size == 1 && anti_terms.nil?

    new_terms = terms.map(&.with_additional_type_arg!(arg)).to_set
    Intersection.new(new_terms, anti_terms)
  end

  def substitute_type_params(
    type_params : Array(TypeParam),
    type_args : Array(MetaType)
  ) : Inner
    result = Unconstrained.instance

    terms.try(&.each { |term|
      result = result.intersect(
        term.substitute_type_params(type_params, type_args)
      )
    })

    anti_terms.try(&.each { |anti_term|
      result = result.intersect(
        anti_term.substitute_type_params(type_params, type_args)
      )
    })

    result
  end

  def each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> _)
    terms.try(&.each(&.each_type_alias_in_first_layer(&block)))
    anti_terms.try(&.each(&.each_type_alias_in_first_layer(&block)))
  end

  def substitute_each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> MetaType) : Inner
    result = Unconstrained.instance

    terms.try(&.each { |term|
      result = result.intersect(term.substitute_each_type_alias_in_first_layer(&block))
    })

    anti_terms.try(&.each { |anti_term|
      result = result.intersect(anti_term.substitute_each_type_alias_in_first_layer(&block))
    })

    result
  end

  def subtype_of?(ctx : Context, other : Nominal) : Bool
    # We don't handle anti-terms here yet. Error if they are present.
    raise NotImplementedError.new("intersection subtyping with anti terms") \
      if anti_terms

    # If we get this far, we know the intersections has at least one term.
    terms = terms().not_nil!

    # This intersection is a subtype of the given nominal if any one term
    # in the intersection is a subtype of that nominal.
    # This is a sufficient condition, but not a necessary one;
    # there are theoretically other ways to succeed if we fail this check.
    return true if terms.any?(&.subtype_of?(ctx, other))

    # If we only had one term, and it failed the above check, then we know we
    # have failed overall; it's only possible to still succeed if we have
    # multiple terms to work with here.
    return false if terms.size == 1

    # However we have not yet implemented this logic.
    # TODO: we may have to do something subtle here when dealing with
    # subtyping of intersections of traits, where multiple traits
    # get inlined into a single composite trait so that they can be
    # properly compared while taking it all simultaneously into account.
    raise NotImplementedError.new("#{self} <: #{other}")
  end

  def supertype_of?(ctx : Context, other : Nominal) : Bool
    # We don't handle anti-terms here yet. Error if they are present.
    raise NotImplementedError.new("intersection supertyping with anti terms") \
      if anti_terms

    # If we get this far, we know the intersections has at least one term.
    terms = terms().not_nil!

    # This intersection is a supertype of the given nominal if and only if
    # all terms in the intersection are a supertype of that nominal.
    terms.all?(&.supertype_of?(ctx, other))
  end

  def subtype_of?(ctx : Context, other : AntiNominal) : Bool
    raise NotImplementedError.new([self, :subtype_of?, other].inspect)
  end

  def supertype_of?(ctx : Context, other : AntiNominal) : Bool
    raise NotImplementedError.new([self, :supertype_of?, other].inspect)
  end

  def subtype_of?(ctx : Context, other : Intersection) : Bool
    return true if self == other

    # We don't handle anti-terms here yet. Error if they are present.
    raise NotImplementedError.new("intersection subtyping with anti terms") \
      if anti_terms || other.anti_terms

    # If we get this far, we know both intersections have at least one term.
    terms = terms().not_nil!
    other_terms = other.terms.not_nil!

    # If we have at least one term that is a subtype of all terms of other,
    # then we know the whole intersection is a subtype of the other.
    # This is a sufficient condition, but not a necessary one;
    # there are theoretically other ways to succeed if we fail this check.
    return true if terms.any? do |term|
      other_terms.all?(&.supertype_of?(ctx, term))
    end

    # If we only had one term, and it failed the above check, then we know we
    # have failed overall; it's only possible to still succeed if we have
    # multiple terms to work with here.
    return false if terms.size == 1

    # However we have not yet implemented this logic.
    # TODO: we may have to do something subtle here when dealing with
    # subtyping of intersections of traits, where multiple traits
    # get inlined into a single composite trait so that they can be
    # properly compared while taking it all simultaneously into account.
    raise NotImplementedError.new("#{self} <: #{other}")

    # If we reach this point, we've passed all checks. Congratulations!
    true
  end

  def supertype_of?(ctx : Context, other : Intersection) : Bool
    other.subtype_of?(ctx, self) # delegate to the above function via symmetry.
  end

  def subtype_of?(ctx : Context, other : (Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def supertype_of?(ctx : Context, other : (Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def satisfies_bound?(ctx : Context, bound : Nominal) : Bool
    # This intersection satisfies the given nominal bound if and only if
    # it has at least one term that satisfies the given nominal bound.
    terms.try do |terms|
      terms.each do |term|
        return true if term.satisfies_bound?(ctx, bound)
      end
    end
    false
  end

  def satisfies_bound?(ctx : Context, bound : Intersection) : Bool
    # If the bound has terms, then we must satisfy each term.
    bound.terms.try do |bound_terms|
      bound_terms.each do |bound_term|
        return false unless self.satisfies_bound?(ctx, bound_term)
      end
    end

    # If the bound has anti-terms, then we don't know how to handle that yet.
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}") \
      if bound.anti_terms

    # If we get to this point, we've satisfied the bound.
    true
  end

  def satisfies_bound?(ctx : Context, bound : (AntiNominal | Union | Unconstrained | Unsatisfiable)) : Bool
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end
end
