class Mare::Compiler::Infer::MetaType::Unsatisfiable
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

  def each_reachable_defn : Iterator(Infer::ReifiedType)
    ([] of Infer::ReifiedType).each
  end

  def find_callable_func_defns(ctx, infer : ForFunc, name : String)
    nil
  end

  def any_callable_func_defn_type(ctx, name : String) : Infer::ReifiedType?
    nil
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

  def ephemeralize
    self # no effect
  end

  def strip_ephemeral
    self # no effect
  end

  def alias
    self # no effect
  end

  def strip_cap
    self # no effect
  end

  def partial_reifications
    Set(Inner).new # no partial reifications are possible
  end

  def type_params
    Set(Refer::TypeParam).new # no type params are present
  end

  def substitute_type_params(substitutions : Hash(Refer::TypeParam, MetaType))
    self # no type params are present to be substituted
  end

  def is_sendable?
    # Unsatisfiable is never sendable - it cannot exist at all.
    # TODO: is this right? it seems so, but breaks symmetry with Unconstrained.
    false
  end

  def safe_to_match_as?(infer : (ForFunc | ForType), other) : Bool?
    raise NotImplementedError.new("#{self.inspect} safe_to_match_as?")
  end

  def viewed_from(origin)
    raise NotImplementedError.new("#{origin.inspect}->#{self.inspect}")
  end

  def extracted_from(origin)
    raise NotImplementedError.new("#{origin.inspect}+>#{self.inspect}")
  end

  def subtype_of?(infer : (ForFunc | ForType), other : Inner) : Bool
    # Unsatisfiable is a subtype of nothing - it cannot exist at all.
    # TODO: is this right? it seems so, but breaks symmetry with Unconstrained.
    false
  end

  def supertype_of?(infer : (ForFunc | ForType), other : Inner) : Bool
    # Unsatisfiable is never a supertype - it is never satisfied.
    false
  end

  def satisfies_bound?(infer : (ForFunc | ForType), bound) : Bool
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end
end
