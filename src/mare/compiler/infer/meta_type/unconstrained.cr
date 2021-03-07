class Mare::Compiler::Infer::MetaType::Unconstrained
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

  def each_reachable_defn(ctx : Context) : Array(Infer::ReifiedType)
    ([] of Infer::ReifiedType)
  end

  def alt_find_callable_func_defns(ctx, infer : AltInfer::Visitor?, name : String)
    nil
  end

  def find_callable_func_defns(ctx, infer : ForReifiedFunc?, name : String)
    nil
  end
  def find_callable_func_defns(ctx, infer : TypeCheck::ForReifiedFunc?, name : String)
    nil
  end

  def any_callable_func_defn_type(ctx, name : String) : Infer::ReifiedType?
    nil
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
    # Return every possible non-ephemeral cap.
    Capability::ALL_NON_EPH.to_set
  end

  def type_params
    Set(TypeParam).new # no type params are present
  end

  def substitute_type_params(substitutions : Hash(TypeParam, MetaType))
    self # no type params are present to be substituted
  end

  def substitute_lazy_type_params(substitutions : Hash(TypeParam, MetaType), max_depth : Int)
    self # no type params are present to be substituted
  end

  def gather_lazy_type_params_referenced(ctx : Context, set : Set(TypeParam), max_depth : Int) : Set(TypeParam)
    set # no type params are present to be gathered
  end

  def is_sendable?
    # Unconstrained is never sendable - it makes no guarantees at all.
    false
  end

  def safe_to_match_as?(ctx : Context, other) : Bool?
    raise NotImplementedError.new("#{self.inspect} safe_to_match_as?")
  end

  def recovered
    self
  end

  def viewed_from(origin)
    raise NotImplementedError.new("#{origin.inspect}->#{self.inspect}")
  end

  def extracted_from(origin)
    raise NotImplementedError.new("#{origin.inspect}->>#{self.inspect}")
  end

  def subtype_of?(ctx : Context, other : Inner) : Bool
    # Unconstrained is a subtype of nothing - it makes no guarantees at all.
    false
  end

  def supertype_of?(ctx : Context, other : Inner) : Bool
    # Unconstrained is a supertype of everything.
    true
  end

  def satisfies_bound?(ctx : Context, bound) : Bool
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end
end
