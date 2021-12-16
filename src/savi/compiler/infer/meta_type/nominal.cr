struct Savi::Compiler::Infer::MetaType::Nominal
  getter defn : ReifiedType | ReifiedTypeAlias | TypeParam

  def initialize(@defn)
  end

  def ignores_cap?
    defn = @defn
    defn.is_a?(ReifiedType) && defn.link.ignores_cap?
  end

  def lazy?
    defn = @defn
    defn.is_a?(ReifiedTypeAlias)
  end

  def inspect(io : IO)
    inspect_without_cap(io)

    io << "'any" unless lazy? || ignores_cap?
  end

  def inspect_with_cap(io : IO, cap : Capability)
    inspect_without_cap(io)

    # If the cap is the same as the default cap, we omit it for brevity.
    # Otherwise, we'll print it here with the same syntax that the programmer
    # can use to specify it explicitly.
    defn = defn()
    unless defn.is_a?(ReifiedType) && cap.value == Cap.from_string(defn.link.cap)
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
      io << defn.ref.ident.value
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

  def gather_call_receiver_span(
    ctx : Context,
    pos : Source::Pos,
    infer : Visitor?,
    name : String
  ) : Span
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    defn = defn()
    case defn
    when ReifiedType
      defn_defn = defn.defn(ctx)
      if defn_defn.find_func?(name)
        Span.simple(MetaType.new_nominal(defn))
      else
        hints = [{defn_defn.ident.pos,
          "#{defn_defn.ident.value} has no '#{name}' member"}]

        found_similar = false
        if name.ends_with?("!")
          defn_defn.find_func?(name[0...-1]).try do |similar|
            found_similar = true
            hints << {similar.ident.pos,
              "maybe you meant to use '#{similar.ident.value}' (without '!')"}
          end
        else
          defn_defn.find_func?("#{name}!").try do |similar|
            found_similar = true
            hints << {similar.ident.pos,
              "maybe you meant to use '#{similar.ident.value}' (with a '!')"}
          end
        end

        unless found_similar
          similar = defn_defn.find_similar_function(name)
          hints << {similar.ident.pos,
            "maybe you meant to use the '#{similar.ident.value}' member"} \
              if similar
        end

        Span.error(pos,
          "The '#{name}' member can't be reached on this receiver", hints
        )
      end
    when TypeParam
      # TODO: get from precalculated variable already saved to Infer Analysis
      infer.not_nil!
        .lookup_type_param_bound_span(ctx, defn)
        .transform_mt_to_span(&.gather_call_receiver_span(ctx, pos, infer, name))
    else
      raise NotImplementedError.new(defn)
    end
  end

  def find_callable_func_defns(ctx, name : String)
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    defn = defn()
    case defn
    when ReifiedType
      func = defn.defn(ctx).find_func?(name)
      [{MetaType.new(self), defn, func}]
    else
      [] of {MetaType, ReifiedType?, Program::Function?}
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

  def aliased
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    self # no effect
  end

  def consumed
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    self # no effect
  end

  def stabilized
    # TODO: Should we use this error?
    # raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

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

  def with_additional_type_arg!(arg : MetaType) : Inner
    defn = defn()
    Nominal.new(
      case defn
      when ReifiedTypeAlias; defn.with_additional_arg(arg)
      when ReifiedType; defn.with_additional_arg(arg)
      else raise NotImplementedError.new("#{self} with_additional_type_arg!")
      end
    )
  end

  def substitute_type_params_retaining_cap(
    type_params : Array(TypeParam),
    type_args : Array(MetaType)
  ) : Inner
    defn = defn()
    case defn
    when TypeParam
      index = type_params.index(defn)
      index ? type_args[index].strip_cap.inner : self
    when ReifiedType
      args = defn.args.map do |arg|
        arg.substitute_type_params_retaining_cap(type_params, type_args).as(MetaType)
      end

      Nominal.new(ReifiedType.new(defn.link, args))
    when ReifiedTypeAlias
      args = defn.args.map do |arg|
        arg.substitute_type_params_retaining_cap(type_params, type_args).as(MetaType)
      end

      Nominal.new(ReifiedTypeAlias.new(defn.link, args))
    else
      raise NotImplementedError.new(defn)
    end
  end

  def each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> _)
    defn = defn()
    defn.is_a?(ReifiedTypeAlias) ? block.call(defn) : nil
  end

  def substitute_each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> MetaType) : Inner
    defn = defn()
    defn.is_a?(ReifiedTypeAlias) ? block.call(defn).inner : self
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

  def viewed_from(origin)
    raise NotImplementedError.new("simplify first to remove aliases") if defn.is_a?(ReifiedTypeAlias)

    # A nominal that ignores capabilities also ignores viewpoint adaptation.
    return self if ignores_cap?

    raise NotImplementedError.new("#{origin.inspect}->#{self.inspect}")
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

    if defn.is_a?(ReifiedType)
      if other_defn.is_a?(ReifiedType)
        return true if defn == other_defn
        # When both sides are ReifiedTypes, delegate to the SubtypingCache.
        ctx.subtyping.is_subtype_of?(ctx, defn, other_defn)
      elsif other_defn.is_a?(TypeParam)
        false
      else
        raise NotImplementedError.new("type <: ?")
      end
    elsif defn.is_a?(TypeParam)
      if other_defn.is_a?(ReifiedType)
        false
      elsif other_defn.is_a?(TypeParam)
        defn.ref == other_defn.ref
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
