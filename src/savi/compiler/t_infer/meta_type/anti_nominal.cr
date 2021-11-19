struct Savi::Compiler::TInfer::MetaType::AntiNominal
  getter defn : ReifiedType

  def initialize(defn)
    raise NotImplementedError.new(defn) unless defn.is_a?(ReifiedType)
    @defn = defn
  end

  def inspect(io : IO)
    io << "-"
    io << defn.link.name
  end

  def each_reachable_defn(ctx : Context) : Array(ReifiedType)
    ([] of ReifiedType)
  end

  def gather_call_receiver_span(
    ctx : Context,
    pos : Source::Pos,
    infer : Visitor?,
    name : String
  ) : Span
    Span.error(pos,
      "The '#{name}' function can't be called on this receiver", [
        {pos, "the type #{self.inspect} has no types defining that function"}
      ]
    )
  end

  def find_callable_func_defns(ctx, name : String)
    nil
  end

  def any_callable_func_defn_type(ctx, name : String) : ReifiedType?
    nil
  end

  def is_concrete?
    defn.link.is_concrete?
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
    Intersection.new(nil, [self, other].to_set)
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
    Union.new(nil, [self, other].to_set)
  end

  def unite(other : (Intersection | Union))
    other.unite(self) # delegate to the "higher" class via commutativity
  end

  def type_params
    defn = defn()
    if defn.is_a?(TypeParam)
      [defn].to_set
    else
      Set(TypeParam).new
    end
  end

  def with_additional_type_arg!(arg : MetaType) : Inner
    raise NotImplementedError.new("#{self} with_additional_type_arg!")
  end

  def substitute_type_params(
    type_params : Array(TypeParam),
    type_args : Array(MetaType)
  ) : Inner
    defn = defn()
    case defn
    when TypeParam
      index = type_params.index(defn)
      index ? type_args[index].strip_cap.inner.negate : self
    when ReifiedType
      args = defn.args.map do |arg|
        arg.substitute_type_params(type_params, type_args).as(MetaType)
      end

      AntiNominal.new(ReifiedType.new(defn.link, args))
    when ReifiedTypeAlias
      args = defn.args.map do |arg|
        arg.substitute_type_params(type_params, type_args).as(MetaType)
      end

      AntiNominal.new(ReifiedTypeAlias.new(defn.link, args))
    else
      raise NotImplementedError.new(defn)
    end
  end

  def each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> _)
    raise NotImplementedError.new("#{self} each_type_alias_in_first_layer")
  end

  def substitute_each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> MetaType) : Inner
    defn = defn()
    defn.is_a?(ReifiedTypeAlias) ? block.call(defn).inner.negate : self
  end

  def subtype_of?(ctx : Context, other : Nominal) : Bool
    # An anti-nominal can never be a subtype of any nominal -
    # it excludes a single nominal, and includes every other possible nominal,
    # so it cannot possibly be as or more specific than a single nominal.
    false
  end

  def supertype_of?(ctx : Context, other : Nominal) : Bool
    # An anti-nominal is a supertype of the given nominal if and only if
    # the other nominal is not a subtype of this defn's nominal.
    !other.subtype_of?(ctx, Nominal.new(defn))
  end

  def subtype_of?(ctx : Context, other : AntiNominal) : Bool
    # An anti-nominal is a subtype of another anti-nominal if and only if
    # all cases excluded by the other anti-nominal are also excluded by it.
    # For this anti-nominal to be as or more exclusive than the other,
    # its defn must be as or more inclusive than the other (a supertype).
    Nominal.new(other.defn).subtype_of?(ctx, Nominal.new(defn))
  end

  def supertype_of?(ctx : Context, other : AntiNominal) : Bool
    # This operation is symmetrical with the above operation.
    other.subtype_of?(ctx, self) # delegate to the above method via symmetry
  end

  def subtype_of?(ctx : Context, other : (Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def supertype_of?(ctx : Context, other : (Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def satisfies_bound?(ctx : Context, bound) : Bool
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end
end
