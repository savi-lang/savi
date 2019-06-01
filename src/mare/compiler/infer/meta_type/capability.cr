struct Mare::Compiler::Infer::MetaType::Capability
  getter name : String
  
  def initialize(@name)
  end
  
  ISO_EPH = new("iso+"); def self.iso_eph; ISO_EPH end
  ISO     = new("iso");  def self.iso;     ISO     end
  TRN_EPH = new("trn+"); def self.trn_eph; TRN_EPH end
  TRN     = new("trn");  def self.trn;     TRN     end
  REF     = new("ref");  def self.ref;     REF     end
  VAL     = new("val");  def self.val;     VAL     end
  BOX     = new("box");  def self.box;     BOX     end
  TAG     = new("tag");  def self.tag;     TAG     end
  NON     = new("non");  def self.non;     NON     end
  
  ALL_NON_EPH = [ISO, TRN, REF, VAL, BOX, TAG, NON]
  
  def inspect(io : IO)
    io << name
  end
  
  def hash : UInt64
    name.hash
  end
  
  def ==(other)
    other.is_a?(Capability) && name == other.name
  end
  
  def each_reachable_defn : Iterator(Infer::ReifiedType)
    ([] of Infer::ReifiedType).each
  end
  
  def find_callable_func_defns(infer : ForFunc, name : String)
    nil
  end
  
  def any_callable_func_defn_type(name : String) : Infer::ReifiedType?
    nil
  end
  
  def negate : Inner
    raise NotImplementedError.new("negate capability")
  end
  
  def intersect(other : Unconstrained)
    self
  end
  
  def intersect(other : Unsatisfiable)
    other
  end
  
  def intersect(other : Capability)
    raise "unsupported intersect: #{self} & #{other}" \
      unless ALL_NON_EPH.includes?(self) && ALL_NON_EPH.includes?(other)
    
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
    
    # We explicitly do not wish to combine capabilities here like we do in
    # the intersect method, even if they are overlapping.
    Union.new([self, other].to_set)
  end
  
  def unite(other : (Nominal | AntiNominal | Intersection | Union))
    other.unite(self) # delegate to the "higher" class via commutativity
  end
  
  def subtype_of?(infer : ForFunc, other : Capability); subtype_of?(other) end
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
  
  def supertype_of?(infer : ForFunc, other : Capability); supertype_of?(other) end
  def supertype_of?(other : Capability) : Bool
    other.subtype_of?(self) # delegate to the above function via symmetry
  end
  
  def subtype_of?(infer : ForFunc, other : (Nominal | AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(infer, self) # delegate to the other class via symmetry
  end
  
  def supertype_of?(infer : ForFunc, other : (Nominal | AntiNominal | Intersection | Union | Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(infer, self) # delegate to the other class via symmetry
  end
  
  def ephemeralize
    # ISO and TRN are the only capabilities which distinguish ephemerality,
    # because they are the only ones that care about reference uniqueness.
    case self
    when ISO then ISO_EPH
    when TRN then TRN_EPH
    else self
    end
  end
  
  def strip_ephemeral
    # ISO and TRN are the only capabilities which distinguish ephemerality,
    # because they are the only ones that care about reference uniqueness.
    case self
    when ISO_EPH then ISO
    when TRN_EPH then TRN
    else self
    end
  end
  
  def alias
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
  
  def partial_reifications
    [self]
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
  
  # def to_generic
  #   case self
  #   when ISO_EPH, TRN_EPH
  #     raise NotImplementedError.new("generic cap of an ephemeral cap")
  #   when ISO, TRN, REF, VAL
  #     self
  #   when BOX
  #     Union.new([BOX, REF, VAL, TRN].to_set)
  #   when TAG
  #     Union.new([TAG, BOX, REF, VAL, ISO, TRN].to_set)
  #   when NON
  #     Union.new([NON, TAG, BOX, REF, VAL, ISO, TRN].to_set)
  #   else
  #     raise NotImplementedError.new("generic cap of #{self}")
  #   end
  # end
  
  def viewed_from(origin : Capability) : Capability
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
