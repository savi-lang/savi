# TODO: Should this be in its own file?
enum Mare::Compiler::Infer::Cap : UInt8
  ISO
  ISO_ALIASED
  REF
  VAL
  BOX
  TAG
  NON

  def inspect; string; end
  def string
    case self
    when ISO;         "iso"
    when ISO_ALIASED; "iso'aliased"
    when REF;         "ref"
    when VAL;         "val"
    when BOX;         "box"
    when TAG;         "tag"
    when NON;         "non"
    end
  end

  def self.from_string(string)
    case string
    when "iso";         ISO
    when "iso'aliased"; ISO_ALIASED
    when "ref";         REF
    when "val";         VAL
    when "box";         BOX
    when "tag";         TAG
    when "non";         NON
    else raise NotImplementedError.new(string)
    end
  end
end

struct Mare::Compiler::Infer::MetaType::Capability
  getter value : (Cap | Set(Cap))

  def initialize(@value)
  end

  def self.build(caps : Set(Cap))
    case caps.size
    when 0 then Unsatisfiable.instance
    when 1 then Capability.new(caps.first)
    else new(caps)
    end
  end

  # Singular capabilities.
  ISO         = new(Cap::ISO)
  ISO_ALIASED = new(Cap::ISO_ALIASED)
  REF         = new(Cap::REF)
  VAL         = new(Cap::VAL)
  BOX         = new(Cap::BOX)
  TAG         = new(Cap::TAG)
  NON         = new(Cap::NON)

  # Canonical generic capability sets.
  ANY   = new([Cap::ISO, Cap::REF, Cap::VAL, Cap::BOX, Cap::TAG, Cap::NON].to_set) # all (non-aliased) caps
  ALIAS = new([Cap::REF, Cap::VAL, Cap::BOX, Cap::TAG, Cap::NON].to_set)           # alias as themselves
  SEND  = new([Cap::ISO, Cap::VAL, Cap::TAG, Cap::NON].to_set)                     # are sendable
  SHARE = new([Cap::VAL, Cap::TAG, Cap::NON].to_set)                               # are sendable & alias as themselves
  READ  = new([Cap::REF, Cap::VAL, Cap::BOX].to_set)                               # are readable & alias as themselves

  def self.new_generic(name)
    case name
    when "any"          then ANY
    when "alias"        then ALIAS
    when "send"         then SEND
    when "share"        then SHARE
    when "read"         then READ
    else raise NotImplementedError.new(name)
    end
  end

  def self.new_maybe_generic(name)
    case name
    when "any"          then ANY
    when "alias"        then ALIAS
    when "send"         then SEND
    when "share"        then SHARE
    when "read"         then READ
    else new(Cap.from_string(name))
    end
  end

  def each_cap
    value = value()
    if value.is_a?(Set(Cap))
      value.each
    else
      [value].each
    end
  end

  def inspect(io : IO)
    value = value()
    if value.is_a?(Set(Cap))
      io << '{'
      value.each_with_index do |cap, index|
        io << ", " unless index == 0
        cap.inspect(io)
      end
      io << '}'
    else
      io << value.string
    end
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

  def negate : Inner
    raise NotImplementedError.new("negate capability")
  end

  def set_intersect(other : Capability)
    v1 = value()
    v2 = other.value

    if v1.is_a?(Set(Cap))
      if v2.is_a?(Set(Cap))
        Capability.new(v1 & v2)
      else
        v1.includes?(v2.as(Cap)) ? other : Unsatisfiable.instance
      end
    else
      if v2.is_a?(Set(Cap))
        v2.includes?(v1.as(Cap)) ? self : Unsatisfiable.instance
      else
        v1.as(Cap) == v2.as(Cap) ? self : Unsatisfiable.instance
      end
    end
  end

  def intersect(other : Unconstrained)
    self
  end

  def intersect(other : Unsatisfiable)
    other
  end

  def intersect(other : Capability) : (Capability | Unsatisfiable)
    value = value()
    other_value = other.value
    if other_value.is_a?(Set(Cap))
      if value.is_a?(Set(Cap))
        return self if other == self
        raise "unsupported intersect: #{self} & #{other}"
      else
        return other.intersect(self)
      end
    elsif value.is_a?(Set(Cap))
      new_value =
        value.map { |cap| Capability.new(cap) }
          .map(&.intersect(other).as(Capability | Unsatisfiable))
          .select(&.is_a?(Capability))
          .map(&.as(Capability).value.as(Cap))
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
    # TODO: Should we return ISO here instead, since it can satisfy any cap?
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
    value = value()
    other_value = other.value

    ##
    # Reference capability subtyping can be visualized using this graph,
    # wherein leftward caps are subtypes of caps that appear to their right,
    # with ISO being a subtype of all, and NON being a supertype of all.
    #
    # Aliased ISO is a supertype of its non-aliased counterpart,
    # and it is the direct subtype of TAG.
    #
    # See George Steed's paper, "A Principled Design of Capabilities in Pony":
    # > https://www.imperial.ac.uk/media/imperial-college/faculty-of-engineering/computing/public/GeorgeSteed.pdf
    #
    #       / REF \
    # ISO <:       <: BOX <: TAG <: NON
    #  ^    \ VAL /           |
    #  |                      |
    #  |                      |
    # ISO& -------------------/

    # A capability always counts as a subtype of itself.
    return true if self == other

    # Otherwise, check the truth table corresponding to the subtyping graph.
    case value
    when Cap::ISO
      true
    when Cap::ISO_ALIASED
      Cap::TAG == other_value || Cap::NON == other_value
    when Cap::REF, Cap::VAL
      Cap::BOX == other_value || Cap::TAG == other_value || Cap::NON == other_value
    when Cap::BOX
      Cap::TAG == other_value || Cap::NON == other_value
    when Cap::TAG
      Cap::NON == other_value
    when Cap::NON
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

  def satisfies_bound?(bound : Capability) : Bool
    return true if value.is_a?(Infer::Cap) && self == bound

    value = value()
    bound_value = bound.value
    if bound_value.is_a?(Set(Cap))
      return true if bound_value.includes?(value)

      if value.is_a?(Set(Cap))
        return true if value.all? { |c| bound_value.includes?(c) }
      end
    end

    false
  end
  def satisfies_bound?(ctx : Context, bound : Capability) : Bool
    satisfies_bound?(bound)
  end

  def satisfies_bound?(ctx : Context, bound : (Nominal | AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    raise NotImplementedError.new("#{self} satisfies_bound? #{bound}")
  end

  def aliased : Capability
    value = value()
    raise "unsupported cap: #{self}" unless value.is_a?(Cap)

    case value
    # The alias of an ISO is the aliased counterpart of it.
    when Cap::ISO then ISO_ALIASED
    else self
    end
  end

  def consumed : Capability
    value = value()
    raise "unsupported cap: #{self}" unless value.is_a?(Cap)

    case value
    # The consumption of an ISO_ALIASED is the non-aliased counterpart of it.
    when Cap::ISO_ALIASED then ISO
    else self
    end
  end

  def stabilized : Capability
    value = value()
    case value
    when Cap
      case value
      # The stable form of an ISO_ALIASED or ISO_ALIASED is the degradation of it that can only do
      # the things not explicitly denied by the uniqueness constraints of them.
      # That is, the alias of ISO (read+write unique) cannot read nor write (TAG).
      when Cap::ISO_ALIASED then Capability.new(Cap::TAG)
      else self
      end
    when Set(Cap)
      Capability.new(value.to_a.map { |cap|
        case cap
        when Cap::ISO_ALIASED then Cap::TAG
        else cap
        end
      }.to_set)
    else raise NotImplementedError.new("#{self} stabilized")
    end
  end

  def strip_cap
    # Stripping a cap out of itself leaves the type totally unconstrained.
    Unconstrained.instance
  end

  def partial_reifications : Set(Cap)
    value = value()
    case value
    when Cap then [self].to_set
    when Set(Cap) then value
    else raise NotImplementedError.new("partial_reifications of #{self}")
    end
  end

  def type_params
    Set(TypeParam).new # no type params are ever referenced by a cap
  end

  def with_additional_type_arg!(arg : MetaType) : Inner
    raise NotImplementedError.new("#{self} with_additional_type_arg!")
  end

  def substitute_type_params_retaining_cap(
    type_params : Array(TypeParam),
    type_args : Array(MetaType)
  ) : Inner
    self # no type params are present to be substituted
  end

  def each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> _)
    nil # no type params are present to be yielded
  end

  def substitute_each_type_alias_in_first_layer(&block : ReifiedTypeAlias -> MetaType) : Inner
    self # to type aliases are present to be substituted
  end

  def is_sendable?
    value = value()

    case value
    when Cap::ISO, Cap::VAL, Cap::TAG, Cap::NON
      true
    when Cap::ISO_ALIASED, Cap::REF, Cap::BOX
      false
    else
      raise NotImplementedError.new("is_sendable? of #{self}")
    end
  end

  def safe_to_match_as?(ctx : Context, other) : Bool?
    supertype_of?(ctx, other) ? true : false
  end

  def is_safe_to_write_to?(destination : Capability) : Bool
    value = value()
    dest_value = destination.value
    raise "unsupported #{self} is_safe_to_write_to #{destination}" \
      unless value.is_a?(Cap) && dest_value.is_a?(Cap)

    # See George Steed's paper, "A Principled Design of Capabilities in Pony":
    # > https://www.imperial.ac.uk/media/imperial-college/faculty-of-engineering/computing/public/GeorgeSteed.pdf

    case dest_value
    when Cap::ISO then true # everything is safe to write to an ephemeral iso
    when Cap::ISO_ALIASED
      Cap::ISO == value || Cap::ISO_ALIASED == value || \
      Cap::VAL == value || Cap::TAG == value || Cap::NON == value
    when Cap::REF then true # everything is safe to write to a ref
    else
      raise NotImplementedError.new "#{self} is_safe_to_write_to #{destination}"
    end
  end

  def viewed_from(origin : Capability) : Capability
    value = value()
    origin_value = origin.value
    raise "unsupported viewed_from: #{origin}->#{self}" \
      unless value.is_a?(Cap) && origin_value.is_a?(Cap)

    ##
    # Viewpoint adaptation table, with columns representing the
    # capability of the field, and rows representing the origin capability:
    #        ISO  ISO& REF  VAL  BOX  TAG  NON
    #      ------------------------------------
    # ISO  | ISO  ISO  ISO  VAL  VAL  TAG  NON
    # ISO& | ISO  ISO& ISO& VAL  TAG  TAG  NON
    # REF  | ISO  ISO& REF  VAL  BOX  TAG  NON
    # VAL  | VAL  VAL  VAL  VAL  VAL  TAG  NON
    # BOX  | VAL  TAG  BOX  VAL  BOX  TAG  NON
    # TAG  | NON  NON  NON  NON  NON  NON  NON
    # NON  | NON  NON  NON  NON  NON  NON  NON
    #
    # Proved safe using prolog code from George Steed's paper, "A Principled Design of Capabilities in Pony":
    # > https://www.imperial.ac.uk/media/imperial-college/faculty-of-engineering/computing/public/GeorgeSteed.pdf
    #
    # But modified from the scheme in that paper in the following ways:
    # - removing TRN and adding NON
    # - renaming ISO- AS ISO, and ISO as ISO& (just a different terminology)
    # - collapsing extracting and non-extracting viewpoints back into one op
    # - completing the 7x7 square by allowing ISO ephemeral on the field side,
    #   since we will use viewpoint adaptation not just for fields but also
    #   for the return values of an auto-recovered call.

    # Knock out the bottom two rows of the table.
    case origin_value
    when Cap::TAG, Cap::NON then return NON
    else
    end

    # Knock out the remainder of three columns of the table.
    case value
    when Cap::VAL, Cap::TAG, Cap::NON then return self
    else
    end

    # Knock out the remainder of the VAL row of the table.
    return VAL if origin_value == Cap::VAL

    # Now we just have a 4x4 table left to cover.
    case origin_value
    when Cap::ISO
      case value
      when Cap::ISO, Cap::ISO_ALIASED, Cap::REF then ISO
      when Cap::BOX                             then VAL
      else raise NotImplementedError.new(self.inspect)
      end
    when Cap::ISO_ALIASED
      case value
      when Cap::ISO                   then ISO
      when Cap::ISO_ALIASED, Cap::REF then ISO_ALIASED
      when Cap::BOX                   then TAG
      else raise NotImplementedError.new(self.inspect)
      end
    when Cap::REF then self
    when Cap::BOX
      case value
      when Cap::ISO           then VAL
      when Cap::ISO_ALIASED   then TAG
      when Cap::REF, Cap::BOX then BOX
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
end
