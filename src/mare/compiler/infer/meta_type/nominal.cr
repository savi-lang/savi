struct Mare::Compiler::Infer::MetaType::Nominal
  getter defn : ReifiedType | ReifiedTypeAlias | TypeParam

  def initialize(@defn)
  end

  def ignores_cap?
    defn = @defn
    defn.is_a?(ReifiedType) && defn.link.ignores_cap?
  end

  def inspect(io : IO)
    inspect_without_cap(io)

    io << "'any" unless ignores_cap? || defn.is_a?(ReifiedTypeAlias)
  end

  def inspect_with_cap(io : IO, cap : Capability)
    inspect_without_cap(io)

    # If the cap is the same as the default cap, we omit it for brevity.
    # Otherwise, we'll print it here with the same syntax that the programmer
    # can use to specify it explicitly.
    defn = defn()
    unless defn.is_a?(ReifiedType) && cap.value == defn.link.cap
      io << "'"
      cap.inspect(io)
    end
  end

  def inspect_without_cap(io : IO)
    defn = defn()
    case defn
    when ReifiedType, ReifiedTypeAlias
      defn.show_type(io)
    when TypeParam
      parent_rt = defn.parent_rt
      if parent_rt
        io << "["
        io << defn.ref.ident.value
        io << " from "
        io << defn.parent_rt.try(&.show_type)
        io << "]"
      else
        io << defn.ref.ident.value
      end
    end
  end

  def each_reachable_defn(ctx : Context) : Array(ReifiedType)
    defn = defn()
    case defn
    when TypeParam
      ([] of ReifiedType)
    when ReifiedType
      [defn]
    when ReifiedTypeAlias
      MetaType.simplify_inner(ctx, self).each_reachable_defn(ctx)
    else
      raise NotImplementedError.new(defn)
    end
  end

  def alt_find_callable_func_defns(ctx, infer : AltInfer::Visitor?, name : String)
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    defn = defn()
    case defn
    when ReifiedType
      func = defn.defn(ctx).find_func?(name)
      [{self, defn, func}]
    when TypeParam
      infer.not_nil!.lookup_type_param_bound(ctx, defn)
        .alt_find_callable_func_defns(ctx, infer, name)
    else
      raise NotImplementedError.new(defn)
    end
  end

  def find_callable_func_defns(ctx, infer : ForReifiedFunc?, name : String)
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    defn = defn()
    case defn
    when ReifiedType
      func = defn.defn(ctx).find_func?(name)
      [{self, defn, func}]
    when TypeParam
      infer.not_nil!.lookup_type_param_bound(defn)
        .find_callable_func_defns(ctx, infer, name)
    else
      raise NotImplementedError.new(defn)
    end
  end

  def any_callable_func_defn_type(ctx, name : String) : ReifiedType?
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    defn = defn()
    if defn.is_a?(ReifiedType)
      func = defn.defn(ctx).find_func?(name)
      defn if func
    end
  end

  def is_concrete?
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    defn = defn()
    defn.is_a?(ReifiedType) && defn.link.is_concrete?
  end

  def is_non_alias_and_concrete?
    return false if defn.is_a?(ReifiedTypeAlias)
    is_concrete?
  end

  def negate : Inner
    AntiNominal.new(defn)
  end

  def intersect(other : Unconstrained)
    self
  end

  def intersect(other : Unsatisfiable)
    other
  end

  def intersect(other : Capability)
    # As a small optimization, we can drop the cap here if we know it's ignored.
    return self if ignores_cap?

    Intersection.new(other, [self].to_set)
  end

  def intersect(other : Nominal)
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    # No change if the two nominal types are identical.
    return self if defn == other.defn

    # Unsatisfiable if the two are concrete types that are not identical.
    return Unsatisfiable.instance \
      if is_non_alias_and_concrete? && other.is_non_alias_and_concrete?

    # Otherwise, this is a new intersection of the two types.
    Intersection.new(nil, [self, other].to_set)
  end

  def intersect(other : (AntiNominal | Intersection | Union))
    other.intersect(self) # delegate to the "higher" class via commutativity
  end

  def unite(other : Unconstrained)
    other
  end

  def unite(other : Unsatisfiable)
    self
  end

  def unite(other : Capability)
    Union.new([other].to_set, [self].to_set)
  end

  def unite(other : Nominal)
    # No change if the two nominal types are identical.
    return self if defn == other.defn

    # Otherwise, this is a new union of the two types.
    Union.new(nil, [self, other].to_set)
  end

  def unite(other : (AntiNominal | Intersection | Union))
    other.unite(self) # delegate to the "higher" class via commutativity
  end

  def ephemeralize
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    self # no effect
  end

  def strip_ephemeral
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    self # no effect
  end

  def alias
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    self # no effect
  end

  def strip_cap
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    self # no effect
  end

  def partial_reifications
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    # Intersect with every possible non-ephemeral cap.
    Capability::ALL_NON_EPH.map(&.intersect(self)).to_set
  end

  def type_params
    defn = defn()
    case defn
    when TypeParam
      [defn].to_set
    when ReifiedType
      defn.args.flat_map(&.type_params.as(Set(TypeParam)).to_a).to_set
    when ReifiedTypeAlias
      defn.args.flat_map(&.type_params.as(Set(TypeParam)).to_a).to_set
    else
      raise NotImplementedError.new(defn)
    end
  end

  def substitute_type_params(substitutions : Hash(TypeParam, MetaType))
    defn = defn()
    case defn
    when TypeParam
      substitutions[defn]?.try(&.inner) || self
    when ReifiedType
      args = defn.args.map do |arg|
        arg.substitute_type_params(substitutions).as(MetaType)
      end

      Nominal.new(ReifiedType.new(defn.link, args))
    when ReifiedTypeAlias
      args = defn.args.map do |arg|
        arg.substitute_type_params(substitutions).as(MetaType)
      end

      Nominal.new(ReifiedTypeAlias.new(defn.link, args))
    else
      raise NotImplementedError.new(defn)
    end
  end

  def is_sendable?
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    # A nominal that ignores capabilities is always sendable.
    return true if ignores_cap?

    # An nominal is never itself sendable -
    # it specifies a single nominal, and says nothing about capabilities.
    false
  end

  def safe_to_match_as?(ctx : Context, other) : Bool?
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    supertype_of?(ctx, other) ? true : nil
  end

  def recovered
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    self
  end

  def viewed_from(origin)
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    # A nominal that ignores capabilities also ignores viewpoint adaptation.
    return self if ignores_cap?

    raise NotImplementedError.new("#{origin.inspect}->#{self.inspect}")
  end

  def extracted_from(origin)
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    # A nominal that ignores capabilities also ignores viewpoint adaptation.
    return self if ignores_cap?

    raise NotImplementedError.new("#{origin.inspect}->>#{self.inspect}")
  end

  def subtype_of?(ctx : Context, other : Capability) : Bool
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    # A nominal that ignores capabilities can be a subtype of any capability.
    return true if ignores_cap?

    # Otherwise, a nominal can never be a subtype of any capability -
    # it specifies a single nominal, and says nothing about capabilities.
    false
  end

  def supertype_of?(ctx : Context, other : Capability) : Bool
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    # A nominal can never be a supertype of any capability -
    # it specifies a single nominal, and says nothing about capabilities.
    false
  end

  def subtype_of?(ctx : Context, other : Nominal) : Bool
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)
    raise NotImplementedError.new("simplify first to remove aliases") if other.defn.is_a?(ReifiedTypeAlias)

    defn = defn()
    other_defn = other.defn()
    errors = [] of Error::Info # TODO: accept this as an argument?

    infer = ctx.type_check.has_started? ? ctx.type_check : ctx.infer

    if defn.is_a?(ReifiedType)
      if other_defn.is_a?(ReifiedType)
        return true if defn == other_defn
        # When both sides are ReifiedTypes, delegate to the SubtypingInfo logic.
        for_rt = if ctx.type_check.has_started?
          ctx.type_check.for_rt(ctx, other_defn.link, other_defn.args).analysis
        else
          ctx.infer[other_defn]
        end
        for_rt.is_supertype_of?(ctx, defn, errors)
      elsif other_defn.is_a?(TypeParam)
        # When the other is a TypeParam, use its bound MetaType and run again.
        l = MetaType.new_nominal(defn)
        other_parent_link = other_defn.ref.parent_link
        if other_parent_link.is_a?(Program::Type::Link)
          r = infer.for_rt(ctx, other_parent_link)
                .lookup_type_param_bound(other_defn).strip_cap
        elsif other_parent_link.is_a?(Program::TypeAlias::Link)
          raise NotImplementedError.new("lookup_type_param_bound for TypeAlias")
        else
          raise NotImplementedError.new(other_parent_link)
        end
        l.subtype_of?(ctx, r.not_nil!)
      else
        raise NotImplementedError.new("type <: ?")
      end
    elsif defn.is_a?(TypeParam)
      if other_defn.is_a?(ReifiedType)
        # When this is a TypeParam, use its bound MetaType and run again.
        l = infer.for_rt(ctx, defn.ref.parent_link.as(Program::Type::Link))
              .lookup_type_param_bound(defn).strip_cap
        r = MetaType.new_nominal(other_defn)
        l.subtype_of?(ctx, r)
      elsif other_defn.is_a?(TypeParam)
        if defn.ref == other_defn.ref
          return true if defn.parent_rt == other_defn.parent_rt
          return true if defn.parent_rt.nil?
          return true if other_defn.parent_rt.nil?
        end
        raise NotImplementedError.new("type param <: type param")
      else
        raise NotImplementedError.new("type param <: ?")
      end
    else
      raise NotImplementedError.new("? <: anything")
    end
  end

  def supertype_of?(ctx : Context, other : Nominal) : Bool
    other.subtype_of?(ctx, self) # delegate to the method above via symmetry
  end

  def subtype_of?(ctx : Context, other : (AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def supertype_of?(ctx : Context, other : (AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def satisfies_bound?(ctx : Context, bound : Capability) : Bool
    # A nominal that ignores capabilities can satisfy any capability.
    return true if ignores_cap?

    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end

  def satisfies_bound?(ctx : Context, bound : Nominal) : Bool
    subtype_of?(ctx, bound)
  end

  def satisfies_bound?(ctx : Context, bound : AntiNominal) : Bool
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end

  def satisfies_bound?(ctx : Context, bound : Intersection) : Bool
    # If the bound has a cap, then we can't satisfy it unless we can ignore it.
    return false if bound.cap && !ignores_cap?

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

  def satisfies_bound?(ctx : Context, bound : Union) : Bool
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end

  def satisfies_bound?(ctx : Context, bound : Unconstrained) : Bool
    true # no constraints; always satisfied
  end

  def satisfies_bound?(ctx : Context, bound : Unsatisfiable) : Bool
    false # never satisfied
  end
end
