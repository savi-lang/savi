module Savi::Compiler::XTypes::Cap
  alias Value = UInt8

  # Each cap is represented as a bitset of five fundamental elements,
  # with each element having an associated semantic meaning.
  BIT_ADDR  = 1u8 << 0 # the reference allows knowing the memory address
  BIT_READ  = 1u8 << 1 # the reference allows reading from the object's memory
  BIT_WRITE = 1u8 << 2 # the reference allows writing to the object's memory
  BIT_HELD  = 1u8 << 3 # the reference holds the object firmly (not borrowed)
  BIT_ROOT  = 1u8 << 4 # the reference has maximum-level access to that object
  BITS_ALL_UNION = BIT_ROOT | BIT_HELD | BIT_WRITE | BIT_READ | BIT_ADDR

  # From these five bits we form a lattice of the useful combinations of them,
  # forming the caps that users can refer to in type expression syntax.
  #
  # In our constants, we use BOX_P and REF_P to refer to `box'` and ref'`,
  # respectively. The "prime" character `'` cannot be used, so we use _P here.
  #
  # The most powerful cap `iso` contains all permission bits, so in type theory
  # it is considered to be the "bottom cap", as it is a subtype of all caps.
  # That is, it is the most specific type and has the most features,
  # so no other cap can be used where an `iso` is expected.
  #
  # Similarly, the weakest cap `non` is considered the "top cap",
  # because it has no bits/features in it that are not also in the other caps,
  # making all other caps subtypes of it (and making it the top supertype).
  #
  # The lattice looks like this, portrayed as a graph with subtypes being below,
  # with `non` as the "top cap" and `iso` as the "bottom cap" in the lattice.
  #
  #     non             (top cap: widest, fewest features, weakest)
  #      |
  #      |
  #     tag
  #      |
  #      |
  #     box'
  #    /   \            (lines show subtyping relationships, with the
  #   /     \            subtype shown below its immediate supertype)
  # ref'    box
  #   \    /   \
  #    \  /     \
  #     ref     val
  #       \     /
  #        \   /
  #         iso         (bottom cap: narrowest, most features, strongest)
  NON   = 0_u8
  TAG   = NON   + BIT_ADDR  # from NON, also know the address
  BOX_P = TAG   + BIT_READ  # from TAG, also allow reading
  REF_P = BOX_P + BIT_WRITE # from BOX_P, also allow writing
  BOX   = BOX_P + BIT_HELD  # from BOX_P, also hold it firmly
  REF   = REF_P + BIT_HELD  # from REF_P, also hold it firmly
  VAL   = BOX   + BIT_ROOT  # from BOX, max perm (no one else can write)
  ISO   = REF   + BIT_ROOT  # from REF, max perm (no one else can read or write)
  #
  # Subtyping is transitive, so if there is a downward path from one cap
  # to another, then those two caps have a subtyping relationship.
  # For example, `val` is a subtype of `non` via the path leading through
  # the intermediate caps `box` and `box'`.
  #
  # Caps that are side by side (like `ref` and `val`) have no direct subtyping
  # relationship to one another, but they have a common "upper bound" (`box`),
  # being the nearest cap which they are both subtypes of, and they have a
  # common "lower bound" (`iso`): the nearest cap that is a subtype of both.
  #
  # For caps that do have a direct subtyping relationship, the subtype itself
  # would be the lower bound and the supertype would be the upper bound.
  #
  # The concepts of upper and lower bounds come into play when dealing with
  # "covariant" type positions (like receiving a return value from a call) vs
  # "contravariant" type positions (like providing an argument to a call).
  # When receiving a value of a certain type, code that uses that value must
  # treat it as its the widest possible type (the upper bound), but when
  # required to provide a value of a certain type, code that provides it
  # must meet the most narrow of the requirements (the lower bound).

  module Logic
    # A convenience method used to easily execute the following self. methods
    # without needing to explicitly specify this as the receiver each time.
    # This is used in tests.
    def self.access
      with self yield
    end

    # We store the caps in a map to reach by name or iterate in order.
    CAPS = {
      iso:   ISO,
      val:   VAL,
      ref:   REF,
      box:   BOX,
      ref_p: REF_P,
      box_p: BOX_P,
      tag:   TAG,
      non:   NON,
    }

    # Convenience functions for checking invariants against all possible caps;
    def self.for_all; CAPS.each_value { |k| yield k }; end
    def self.for_all_2
      for_all { |k1|
        for_all { |k2|
          yield k1, k2
        }
      }
    end
    def self.for_all_3
      for_all { |k1|
        for_all { |k2|
          for_all { |k3|
            yield k1, k2, k3
          }
        }
      }
    end

    # Convenience functions for checking bits of a cap value.
    def self.bit_addr?(k : Value); k & BIT_ADDR != 0; end
    def self.bit_read?(k : Value); k & BIT_READ != 0; end
    def self.bit_write?(k : Value); k & BIT_WRITE != 0; end
    def self.bit_held?(k : Value); k & BIT_HELD != 0; end
    def self.bit_root?(k : Value); k & BIT_ROOT != 0; end

    def self.is_subtype?(sub : Value, supr : Value)
      # If the desired subtyping relationship is true,
      # then sub must be the lower bound of the two.
      lower_bound(sub, supr) == sub
    end

    def self.is_supertype?(supr : Value, sub : Value)
      # If the desired subtyping relationship is true,
      # then supr must be the upper bound of the two.
      upper_bound(supr, sub) == supr
    end

    def self.lower_bound(k1 : Value, k2 : Value)
      # The lower bound must have all features of both `k1` and `k2`,
      # hence it is the bitwise union their feature bits.
      k1 | k2
    end

    def self.upper_bound(k1 : Value, k2 : Value)
      # The upper bound must have no features that aren't in both `k1` and `k2`,
      # hence it is the bitwise intersection their feature bits.
      k1 & k2
    end

    def self.aliased(k : Value)
      # The alias of iso is ref'. All other caps alias as themselves.
      k == ISO ? REF_P : k
    end

    def self.viewpoint(k1 : Value, k2 : Value)
      # For purposes of this function we treat the operator as commutative,
      # though one additional wrinkle is that `tag` is not symmetrical -
      # `tag` fields may be read as `tag` from any readable type, but it should
      # not be possible to get readable fields as `tag` from a `tag` origin.
      # We cover that small wrinkle with its own dedicated check in the
      # type-checking pass, but in practice it is not an issue when all getter
      # methods are defined by the compiler as having the `box` capability
      # (and are thus not callable with a `tag` receiver).
      #
      # Thus we can cleanly treat this operation as commutative here,
      # without worrying about the order of the arguments `k1` and `k2`.
      # Prepare a matrix-form table which represents the viewpoint adaptation rules.
      #
      #                 iso   val   ref   box   ref'  box'  tag   non
      #               +------------------------------------------------+
      # origin: iso   | iso   val   iso   val   iso   val   tag   non  |
      # origin: val   | val   val   val   val   val   val   tag   non  |
      # origin: ref   | iso   val   ref   box   ref'  box'  tag   non  |
      # origin: box   | val   val   box   box   box'  box'  tag   non  |
      # origin: ref'  | iso   val   ref'  box'  ref'  box'  tag   non  |
      # origin: box'  | val   val   box'  box'  box'  box'  tag   non  |
      # origin: tag   | tag   tag   tag   tag   tag   tag   tag   non  |
      # origin: non   | non   non   non   non   non   non   non   non  |

      # Unless both inputs have the `addr` bit, we must return `non` (no `addr`)
      return NON unless bit_addr?(k1) && bit_addr?(k2)

      # Unless both inputs have the `read` bit, we must return `tag` (no `read`)
      return TAG unless bit_read?(k1) && bit_read?(k2)

      # If we have `addr` and `read` bits, we must at least be `box'`,
      # which is the uppermost cap in the lattice below `non` and `tag`,
      # and the last descending cap that is a supertype of all other caps.
      result = BOX_P

      # If both inputs have the `write` bit, so does the result.
      result |= BIT_WRITE if bit_write?(k1) && bit_write?(k2)

      # If both inputs have the `held` bit, so does the result.
      result |= BIT_HELD if bit_held?(k1) && bit_held?(k2)

      # If *EITHER* has the `root` bit, the result has both `root` and `held`.
      result |= BIT_ROOT | BIT_HELD if bit_root?(k1) || bit_root?(k2)

      result
    end

    # Return the weakest cap that can be "split" into the two given caps.
    # If the two given caps cannot simultaneously coexist in the same scope,
    # then this function returns nil as an indication of the error.
    def self.simult?(k1 : Value?, k2 : Value?) : Value?
      return nil unless k1 && k2

      if k1 == VAL || k2 == VAL
        return nil if bit_write?(k1 ^ k2)
        return VAL
      end

      upper_bound = upper_bound(k1, k2)
      lower_bound = lower_bound(k1, k2)
      return nil if bit_root?(lower_bound) && bit_read?(upper_bound)

      lower_bound |= BIT_HELD if bit_read?(upper_bound)

      lower_bound
    end

    # Return the weakest cap that can be temporarily aliased as the given
    # "during_alias" cap, then be recovered to be used as the given "post_alias"
    # cap after the "during_alias" cap has gone out of scope.
    def self.sequ?(during_alias : Value?, post_alias : Value?) : Value?
      return nil unless during_alias && post_alias

      if during_alias == VAL
        return nil if bit_write?(post_alias)
        return VAL
      end

      if post_alias == VAL
        return ISO if during_alias == REF_P
        return nil if bit_write?(during_alias)
        return VAL
      end

      return nil if during_alias == ISO && bit_read?(post_alias)
      return nil if post_alias == ISO && bit_held?(during_alias)

      lower_bound(during_alias, post_alias)
    end
  end
end
