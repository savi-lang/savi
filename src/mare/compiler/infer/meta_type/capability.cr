struct Mare::Compiler::Infer::MetaType::Capability
  getter value : (String | Set(Capability))

  def initialize(@value)
  end

  def self.build(caps : Set(Capability))
    case caps.size
    when 0 then Unsatisfiable.instance
    when 1 then caps.first
    else new(caps)
    end
  end

  ISO_EPH = new("iso+")
  ISO     = new("iso")
  TRN_EPH = new("trn+")
  TRN     = new("trn")
  REF     = new("ref")
  VAL     = new("val")
  BOX     = new("box")
  TAG     = new("tag")
  NON     = new("non")

  ALL_NON_EPH = [ISO, TRN, REF, VAL, BOX, TAG, NON]
  ALL_SINGLE = [ISO_EPH, TRN_EPH] + ALL_NON_EPH

  ANY          = new([ISO, TRN, REF, VAL, BOX, TAG, NON].to_set) # all (non-ephemeral) caps
  ALIAS        = new([REF, VAL, BOX, TAG, NON].to_set)           # alias as themselves
  SEND         = new([ISO, VAL, TAG, NON].to_set)                # are sendable
  SHARE        = new([VAL, TAG, NON].to_set)                     # are sendable & alias as themselves
  READ         = new([REF, VAL, BOX].to_set)                     # are readable & alias as themselves
  MUTABLE      = new([ISO, TRN, REF].to_set)                     # are mutable
  MUTABLE_PLUS = new([ISO_EPH, TRN_EPH, ISO, TRN, REF].to_set)   # are mutable, incl ephemeral

  def self.new_generic(name)
    case name
    when "any"         then ANY
    when "alias"       then ALIAS
    when "send"        then SEND
    when "share"       then SHARE
    when "read"        then READ
    when "mutable"     then MUTABLE
    when "mutableplus" then MUTABLE_PLUS # TODO: can this special case for <<= be removed somehow?
    else raise NotImplementedError.new(name)
    end
  end

  def self.new_maybe_generic(name)
    case name
    when "any"         then ANY
    when "alias"       then ALIAS
    when "send"        then SEND
    when "share"       then SHARE
    when "read"        then READ
    when "mutable"     then MUTABLE
    when "mutableplus" then MUTABLE_PLUS # TODO: can this special case for <<= be removed somehow?
    else new(name)
    end
  end

  def each_cap
    value = value()
    if value.is_a?(Set(Capability))
      value.each
    else
      [self].each
    end
  end

  def inspect(io : IO)
    value = value()
    if value.is_a?(Set(Capability))
      io << '{'
      value.each_with_index do |cap, index|
        io << ", " unless index == 0
        cap.inspect(io)
      end
      io << '}'
    else
      io << value
    end
  end

  def each_reachable_defn : Iterator(ReifiedType)
    ([] of ReifiedType).each
  end

  def find_callable_func_defns(ctx, infer : ForFunc, name : String)
    nil
  end

  def any_callable_func_defn_type(ctx, name : String) : ReifiedType?
    nil
  end

  def negate : Inner
    raise NotImplementedError.new("negate capability")
  end

  def set_intersect(other : Capability)
    v1 = value()
    v2 = other.value

    if v1.is_a?(Set(Capability))
      if v2.is_a?(Set(Capability))
        Capability.new(v1 & v2)
      else
        v1.includes?(v2.as(String)) ? other : Unsatisfiable.instance
      end
    else
      if v2.is_a?(Set(Capability))
        v2.includes?(v1.as(String)) ? self : Unsatisfiable.instance
      else
        v1.as(String) == v2.as(String) ? self : Unsatisfiable.instance
      end
    end
  end

  def intersect(other : Unconstrained)
    self
  end

  def intersect(other : Unsatisfiable)
    other
  end

  def intersect(other : Capability)
    if !ALL_SINGLE.includes?(other)
      if !ALL_SINGLE.includes?(self)
        raise "unsupported intersect: #{self} & #{other}"
      else
        return other.intersect(self)
      end
    elsif !ALL_SINGLE.includes?(self)
      value = value().as(Set(Capability))
      new_value =
        value.map(&.intersect(other).as(Capability | Unsatisfiable))
          .select(&.is_a?(Capability))
          .map(&.as(Capability))
          .to_set
      return Capability.build(new_value)
    end
    # If we get to this point, we are dealing with two single caps.

    # If the two are equivalent, return the cap.
    return self if self == other

    # If one cap is a subtype of the other cap, return the subtype because
    # it is the most specific type of the two.
    return self if self.subtype_of?(other)
    return other if other.subtype_of?(self)

    # If the two are unrelated by subtyping, this intersection is unsatisfiable.
    Unsatisfiable.instance
  end

  def intersect(other : (Nominal | AntiNominal | Intersection | Union))
    other.intersect(self) # delegate to the "higher" class via commutativity
  end

  def unite(other : Unconstrained)
    other
  end

  def unite(other : Unsatisfiable)
    self
  end

  def unite(other : Capability)
    return self if self == other

    # If one cap is a subtype of the other cap, return the supertype because
    # it is the most specific type of the two.
    return other if self.subtype_of?(other)
    return self if other.subtype_of?(self)

    # If the two are unrelated by subtyping, return as a union.
    Union.new([self, other].to_set)
  end

  def unite(other : (Nominal | AntiNominal | Intersection | Union))
    other.unite(self) # delegate to the "higher" class via commutativity
  end

  def subtype_of?(ctx : Context, other : Capability); subtype_of?(other) end
  def subtype_of?(other : Capability) : Bool
    ##
    # Reference capability subtyping can be visualized using this graph,
    # wherein leftward caps are subtypes of caps that appear to their right,
    # with ISO+ being a subtype of all, and NON being a supertype of all.
    #
    # Non-ephemeral ISO and TRN are supertypes of their ephemeral counterparts,
    # and they are the direct subtypes of TAG and BOX, respectively.
    #
    # See George Steed's paper, "A Principled Design of Capabilities in Pony":
    # > https://www.imperial.ac.uk/media/imperial-college/faculty-of-engineering/computing/public/GeorgeSteed.pdf
    #
    #                / REF \
    # ISO+ <: TRN+ <:       <: BOX <: TAG <: NON
    #  ^       ^     \ VAL /    |      |
    #  |       |                |      |
    #  |      TRN  <: ----------/      |
    # ISO  <: -------------------------/

    # A capability always counts as a subtype of itself.
    return true if self == other

    # Otherwise, check the truth table corresponding to the subtyping graph.
    case self
    when ISO_EPH
      true
    when TRN_EPH
      other != ISO_EPH && other != ISO
    when ISO
      TAG == other || NON == other
    when TRN, REF, VAL
      BOX == other || TAG == other || NON == other
    when BOX
      TAG == other || NON == other
    when TAG
      NON == other
    when NON
      false
    else
      raise NotImplementedError.new("#{self} <: #{other}")
    end
  end

  def supertype_of?(ctx : Context, other : Capability); supertype_of?(other) end
  def supertype_of?(other : Capability) : Bool
    other.subtype_of?(self) # delegate to the above function via symmetry
  end

  def subtype_of?(ctx : Context, other : (Nominal | AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def supertype_of?(ctx : Context, other : (Nominal | AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(ctx, self) # delegate to the other class via symmetry
  end

  def satisfies_bound?(ctx : Context, bound : Capability) : Bool
    return true if value.is_a?(String) && self == bound

    value = value()
    bound_value = bound.value
    if bound_value.is_a?(Set(Capability))
      return true if bound_value.includes?(self)

      if value.is_a?(Set(Capability))
        return true if value.all? { |c| bound_value.includes?(c) }
      end
    end

    false
  end

  def satisfies_bound?(ctx : Context, bound : (Nominal | AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end

  def ephemeralize
    raise "unsupported cap: #{self}" unless ALL_SINGLE.includes?(self)

    # ISO and TRN are the only capabilities which distinguish ephemerality,
    # because they are the only ones that care about reference uniqueness.
    case self
    when ISO then ISO_EPH
    when TRN then TRN_EPH
    else self
    end
  end

  def strip_ephemeral
    raise "unsupported cap: #{self}" unless ALL_SINGLE.includes?(self)

    # ISO and TRN are the only capabilities which distinguish ephemerality,
    # because they are the only ones that care about reference uniqueness.
    case self
    when ISO_EPH then ISO
    when TRN_EPH then TRN
    else self
    end
  end

  def alias
    raise "unsupported cap: #{self}" unless ALL_SINGLE.includes?(self)

    case self
    # The alias of an ISO+ or TRN+ is the non-ephemeral counterpart of it.
    when ISO_EPH then ISO
    when TRN_EPH then TRN
    # The alias of an ISO or TRN is the degradation of it that can only do
    # the things not explicitly denied by the uniqueness constraints of them.
    # That is, the alias of ISO (read+write unique) cannot read nor write (TAG),
    # and the alias of TRN (write unique) can only read and not write (BOX).
    when ISO then TAG
    when TRN then BOX
    else self
    end
  end

  def strip_cap
    # Stripping a cap out of itself leaves the type totally unconstrained.
    Unconstrained.instance
  end

  def partial_reifications : Set(Capability)
    value = value()
    case value
    when String then [self].to_set
    when Set(Capability) then value
    else raise NotImplementedError.new("partial_reifications of #{self}")
    end
  end

  def type_params
    Set(TypeParam).new # no type params are ever referenced by a cap
  end

  def substitute_type_params(substitutions : Hash(Refer::TypeParam, MetaType))
    self # no type params are present to be substituted
  end

  def is_sendable?
    case self
    when ISO_EPH, TRN_EPH
      raise NotImplementedError.new("is_sendable? of an ephemeral cap")
    when ISO, VAL, TAG, NON
      true
    when TRN, REF, BOX
      false
    else
      raise NotImplementedError.new("is_sendable? of #{self}")
    end
  end

  def safe_to_match_as?(ctx : Context, other) : Bool?
    supertype_of?(ctx, other) ? true : false
  end

  def viewed_from(origin : Capability) : Capability
    raise "unsupported viewed_from: #{origin}->#{self}" \
      unless ALL_NON_EPH.includes?(self) && ALL_SINGLE.includes?(origin)

    ##
    # Non-extracting viewpoint adaptation table, with columns representing the
    # capability of the field, and rows representing the origin capability:
    #        ISO  TRN  REF  VAL  BOX  TAG  NON
    #      ------------------------------------
    # ISO+ | ISO+ ISO+ ISO+ VAL  VAL  TAG  NON
    # ISO  | ISO  ISO  ISO  VAL  TAG  TAG  NON
    # TRN+ | ISO+ TRN+ TRN+ VAL  VAL  TAG  NON
    # TRN  | ISO  TRN  TRN  VAL  BOX  TAG  NON
    # REF  | ISO  TRN  REF  VAL  BOX  TAG  NON
    # VAL  | VAL  VAL  VAL  VAL  VAL  TAG  NON
    # BOX  | TAG  BOX  BOX  VAL  BOX  TAG  NON
    # TAG  | NON  NON  NON  NON  NON  NON  NON
    # NON  | NON  NON  NON  NON  NON  NON  NON
    #
    # See George Steed's paper, "A Principled Design of Capabilities in Pony":
    # > https://www.imperial.ac.uk/media/imperial-college/faculty-of-engineering/computing/public/GeorgeSteed.pdf

    case origin
    when TAG, NON then return NON
    end

    case self
    when TAG, NON then return self
    end

    case origin
    when ISO_EPH
      case self
      when ISO, TRN, REF then ISO_EPH
      when VAL, BOX      then VAL
      else raise NotImplementedError.new(self.inspect)
      end
    when ISO
      case self
      when ISO, TRN, REF then ISO
      when VAL           then VAL
      when BOX           then TAG
      else raise NotImplementedError.new(self.inspect)
      end
    when TRN_EPH
      case self
      when ISO      then ISO_EPH
      when TRN, REF then TRN_EPH
      when VAL, BOX then VAL
      else raise NotImplementedError.new(self.inspect)
      end
    when TRN
      case self
      when ISO      then ISO
      when TRN, REF then TRN
      when BOX      then BOX
      when VAL      then VAL
      else raise NotImplementedError.new(self.inspect)
      end
    when REF then self
    when VAL then VAL
    when BOX
      case self
      when VAL           then VAL
      when TRN, REF, BOX then BOX
      when ISO           then TAG
      else raise NotImplementedError.new(self.inspect)
      end
    else raise NotImplementedError.new(origin.inspect)
    end
  end

  def viewed_from(origin : Union)
    raise NotImplementedError.new(origin.inspect) \
      if origin.terms || origin.anti_terms || origin.intersects

    new_caps =
      origin.caps.not_nil!.map { |origin_cap| viewed_from(origin_cap) }

    Union.build(new_caps.to_set)
  end

  def extracted_from(origin : Capability) : Capability
    raise "unsupported extracted_from: #{origin}->>#{self}" \
      unless ALL_NON_EPH.includes?(self) && ALL_SINGLE.includes?(origin)

    ##
    # Extracting viewpoint adaptation table, with columns representing the
    # capability of the field, and rows representing the origin capability:
    #        ISO  TRN  REF  VAL  BOX  TAG  NON
    #      ------------------------------------
    # ISO+ | ISO+ ISO+ ISO+ VAL  VAL  TAG  NON
    # ISO  | ISO+ VAL  TAG  VAL  TAG  TAG  NON
    # TRN+ | ISO+ TRN+ TRN+ VAL  VAL  TAG  NON
    # TRN  | ISO+ VAL  BOX  VAL  BOX  TAG  NON
    # REF  | ISO+ TRN+ REF  VAL  BOX  TAG  NON
    #
    # See George Steed's paper, "A Principled Design of Capabilities in Pony":
    # > https://www.imperial.ac.uk/media/imperial-college/faculty-of-engineering/computing/public/GeorgeSteed.pdf

    case origin
    when VAL, BOX, TAG, NON then
      raise "can't extract from non-writable cap #{origin}"
    end

    case self
    when TAG, NON then return self
    end

    case origin
    when ISO_EPH
      case self
      when ISO, TRN, REF then ISO_EPH
      when VAL, BOX      then VAL
      else raise NotImplementedError.new(self.inspect)
      end
    when ISO
      case self
      when ISO      then ISO_EPH
      when TRN, VAL then VAL
      when REF, BOX then TAG
      else raise NotImplementedError.new(self.inspect)
      end
    when TRN_EPH
      case self
      when ISO      then ISO_EPH
      when TRN, REF then TRN_EPH
      when VAL, BOX then VAL
      else raise NotImplementedError.new(self.inspect)
      end
    when TRN
      case self
      when ISO      then ISO_EPH
      when TRN, VAL then VAL
      when REF, BOX then BOX
      else raise NotImplementedError.new(self.inspect)
      end
    when REF then self.ephemeralize
    else raise NotImplementedError.new(origin.inspect)
    end
  end

  def extracted_from(origin : Union)
    raise NotImplementedError.new(origin.inspect) \
      if origin.terms || origin.anti_terms || origin.intersects

    new_caps =
      origin.caps.not_nil!.map { |origin_cap| extracted_from(origin_cap) }

    Union.build(new_caps.to_set)
  end
end
