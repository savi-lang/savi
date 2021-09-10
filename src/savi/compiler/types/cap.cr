module Savi::Compiler::Types::Cap
  alias Value = UInt8

  # Each cap is represented as one of the bits in a byte.
  # We have fewer than 8 caps, so not all of the bits are in use.
  ISO = 1u8 << 6
  ILS = 1u8 << 5 # we refer to `iso'aliased` as `ILS` here for short
  REF = 1u8 << 4
  VAL = 1u8 << 3
  BOX = 1u8 << 2
  TAG = 1u8 << 1
  NON = 1u8 << 0

  ISO_ALIASED = ILS

  module Logic
    # A convenience method used to easily execute the following self. methods
    # without needing to explicitly specify this as the receiver each time.
    # This is used in tests.
    def self.access
      with self yield
    end

    # We store the caps in a map to reach them by name or iterate in order.
    BITS = {
      iso: ISO,
      ils: ILS,
      ref: REF,
      val: VAL,
      box: BOX,
      tag: TAG,
      non: NON,
    }

    # Prepare a UInt8 mask that represents all possible bits we use.
    UNION_ALL_BITS = (1u8 << BITS.size) - 1

    # Wrap/unwrap a pair of cap values to/from a single packed integer.
    # This is used to construct/deconstruct the index to a 2D truth table.
    def self.wrap_pair(hi_bits : UInt8, lo_bits : UInt8) : UInt16
      ((UNION_ALL_BITS & lo_bits).to_u16) |
      ((UNION_ALL_BITS & hi_bits).to_u16 << BITS.size)
    end
    def self.unwrap_pair(pair_bits : UInt16) : {UInt8, UInt8}
      lo_bits = UNION_ALL_BITS & pair_bits
      hi_bits = UNION_ALL_BITS & (pair_bits >> BITS.size)
      {hi_bits, lo_bits}
    end

    # Prepare a UInt16 mask that represents all possible bits for two caps,
    # which is used as the lookup index mask for 2D truth tables.
    UNION_ALL_BITS_PAIR = wrap_pair(UNION_ALL_BITS, UNION_ALL_BITS)

    # Prepare a matrix-form table which represents the viewpoint adaptation rules.
    VIEWPOINTS_MATRIX = [
    #  ISO  ILS  REF  VAL  BOX  TAG  NON
      [ISO, ISO, ISO, VAL, VAL, TAG, NON], # viewed from ISO
      [ISO, ILS, ILS, VAL, TAG, TAG, NON], # viewed from ILS
      [ISO, ILS, REF, VAL, BOX, TAG, NON], # viewed from REF
      [VAL, VAL, VAL, VAL, VAL, TAG, NON], # viewed from VAL
      [VAL, TAG, BOX, VAL, BOX, TAG, NON], # viewed from BOX
      [NON, NON, NON, NON, NON, NON, NON], # viewed from TAG
      [NON, NON, NON, NON, NON, NON, NON], # viewed from NON
    ]

    # Convert them into three flat-indexed truth tables, with each possible pair
    # of inputs having a table that can be used to get the third term.
    GET_ADAPTED_BY_ORIGIN_AND_FIELD = Array(UInt8).new(UNION_ALL_BITS_PAIR + 1, 0)
    GET_FIELD_BY_ORIGIN_AND_ADAPTED = Array(UInt8).new(UNION_ALL_BITS_PAIR + 1, 0)
    GET_ORIGIN_BY_FIELD_AND_ADAPTED = Array(UInt8).new(UNION_ALL_BITS_PAIR + 1, 0)
    (0_u16..UNION_ALL_BITS_PAIR).map { |pair_bits|
      origin_bits, field_bits = unwrap_pair(pair_bits)
      adapted_bits : UInt8 = 0

      BITS.values.each_with_index { |origin_mask, origin_index|
        next unless (origin_mask & origin_bits) != 0

        BITS.values.each_with_index { |field_mask, field_index|
          next unless (field_mask & field_bits) != 0

          adapted_bits |= VIEWPOINTS_MATRIX[origin_index][field_index]
        }
      }

      origin_and_field_bits = wrap_pair(origin_bits, field_bits)
      origin_and_adapted_bits = wrap_pair(origin_bits, adapted_bits)
      field_and_adapted_bits = wrap_pair(field_bits, adapted_bits)

      GET_ADAPTED_BY_ORIGIN_AND_FIELD[origin_and_field_bits] |= adapted_bits
      GET_FIELD_BY_ORIGIN_AND_ADAPTED[origin_and_adapted_bits] |= field_bits
      GET_ORIGIN_BY_FIELD_AND_ADAPTED[field_and_adapted_bits] |= origin_bits
    }

    def self.get_adapted_by_origin_and_field(origin, field)
      GET_ADAPTED_BY_ORIGIN_AND_FIELD[wrap_pair(origin, field)]
    end
    def self.get_field_by_origin_and_adapted(origin, adapted)
      GET_FIELD_BY_ORIGIN_AND_ADAPTED[wrap_pair(origin, adapted)]
    end
    def self.get_origin_by_field_and_adapted(field, adapted)
      GET_ORIGIN_BY_FIELD_AND_ADAPTED[wrap_pair(field, adapted)]
    end
  end
end
