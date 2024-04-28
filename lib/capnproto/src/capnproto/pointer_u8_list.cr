struct CapnProto::Pointer::U8List
  @segment : CapnProto::Segment
  @byte_offset : UInt32
  @byte_count : UInt32

  def self.empty(segment)
    new(segment, 0, 0)
  end

  private def initialize(@segment, @byte_offset, @byte_count)
  end

  def to_bytes
    Bytes.new(
      @segment.bytes.to_unsafe + @byte_offset,
      @byte_count,
      read_only: true,
    )
  end

  def to_s
    count = @byte_count
    if count > 0 && @segment.bytes[@byte_offset + count - 1] == 0
      count -= 1
    end
    String.new(Bytes.new(
      @segment.bytes.to_unsafe + @byte_offset,
      count,
      read_only: true,
    ))
  end

  def self.parse_from(
    segment : CapnProto::Segment,
    current_offset : UInt32,
    value : UInt64
  ) : CapnProto::Pointer::U8List
    # Quick bailout path for null pointers.
    return self.empty(segment) if value == 0

    # Handle the case that this may be a far pointer, pointing to the pointer.
    override_byte_offset = 0xffffffff_u32
    far = CapnProto::Pointer::Far.parse_from(
      segment.segments, current_offset, value
    )
    if far
      segment = far.segment
      current_offset = far.byte_offset
      override_byte_offset = far.override_byte_offset
      value = far.pointer_value
    end

    # lsb                       list pointer                        msb
    # +-+-----------------------------+--+----------------------------+
    # |A|             B               |C |             D              |
    # +-+-----------------------------+--+----------------------------+

    # A (2 bits) = 1, to indicate that this is a list pointer.
    # B (30 bits) = Offset, in words, from the end of the pointer to the
    #     start of the first element of the list.  Signed.
    # C (3 bits) = Size of each element:
    #     0 = 0 (e.g. List(Void))
    #     1 = 1 bit
    #     2 = 1 byte
    #     3 = 2 bytes
    #     4 = 4 bytes
    #     5 = 8 bytes (non-pointer)
    #     6 = 8 bytes (pointer)
    #     7 = composite (see below)
    # D (29 bits) = Size of the list:
    #     when C <> 7: Number of elements in the list.
    #     when C = 7: Number of words in the list, not counting the tag word
    #     (see below).

    # The 2 least significant bits (A) encode the pointer kind.
    # Return empty if this is not coded as a list pointer (kind one).
    return self.empty(segment) if (value & 0b11_u64).to_u8 != 1_u8
    lower_u32 = value.to_u32! ^ 0b1_u32

    # The 3 least significant bits of the upper half (C) encode the size class.
    # Return empty if this is not coded as a byte pointer.
    upper_u32 = (value >> 32).to_u32
    return self.empty(segment) \
      if (upper_u32 & 0b111_u32).to_u8 != \
        CapnProto::Meta::ElementSize::Byte.to_u8

    # The bottom 32 bits of the value (excluding the 2 least significant bits
    # (which we have already cleared to zero using the xor operation above),
    # encode a 30-bit signed integer (B) indicating the offset in 8-byte words
    # to the pointed-to location within the segment, from the current offset.
    #
    # Given that we know the lowest two bits are zero, we can treat this
    # as a 32-bit signed integer indicating half of the actual offset,
    # because multiplying by 4 is the same as bit shifting rightward by 2,
    # and 4 is half of the factor of 8 we need to mutiply by to translate
    # the offset from units of 8-byte words to units of bytes.
    offset_half = lower_u32.to_i32!
    byte_offset = (current_offset.to_i32 + 8 + offset_half + offset_half).to_u32
    if override_byte_offset != 0xffffffff_u32
      byte_offset = override_byte_offset
    end

    # The upper 32-bits of the value, excluding the least significant 3 bits,
    # (D) indicate the number of elements in the list, which is the same as
    # the number of bytes in the list, because this list is of the byte class.
    byte_count = (upper_u32 >> 3).to_u32

    self.new(segment, byte_offset, byte_count)
  end
end
