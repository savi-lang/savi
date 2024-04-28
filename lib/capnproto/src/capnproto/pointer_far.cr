struct CapnProto::Pointer::Far
  getter segment : CapnProto::Segment
  getter byte_offset : UInt32
  getter override_byte_offset : UInt32
  getter pointer_value : UInt64

  def initialize(@segment, @byte_offset, @override_byte_offset, @pointer_value)
  end

  def self.parse_from(
    segments : Array(CapnProto::Segment),
    current_offset : UInt32,
    value : UInt64
  ) : CapnProto::Pointer::Far?
    # lsb                        far pointer                        msb
    # +-+-+---------------------------+-------------------------------+
    # |A|B|            C              |               D               |
    # +-+-+---------------------------+-------------------------------+

    # A (2 bits) = 2, to indicate that this is a far pointer.
    # B (1 bit) = 0 if the landing pad is one word, 1 if it is two words.
    #     See explanation below.
    # C (29 bits) = Offset, in words, from the start of the target segment
    #     to the location of the far-pointer landing-pad within that
    #     segment.  Unsigned.
    # D (32 bits) = ID of the target segment.  (Segments are numbered
    #     sequentially starting from zero.)

    # The 2 least significant bits (A) encode the pointer kind.
    # Raise an error if this is not coded as a list pointer (kind two).
    # The next bit (B) is set only in the rare case of a "double far" pointer.
    return nil if (value & 0b11_u64).to_u8 != 2_u8
    is_double_far = (value & 0b100_u64).to_u8 == 0b100_u8

    # The bottom 32 bits of the value (excluding the 3 least significant bits
    # mentioned above), encode a 29-bit unsigned integer (C) indicating the
    # absolute offset in 8-byte words of a location within the target segment.
    #
    # Using a bit mask to zero out the bottom three bits, we can treat the
    # 29-bit integer in units of 8-byte words as if it were a 32-bit integer
    # in units of bytes, because the 3 zero bits represent a factor of 8.
    byte_offset = (value & 0xfffffff8_u64).to_u32

    # The upper 32-bits of the value (D), represent the segment ID, as an
    # index into the list of segments to point to the target segment.
    segment_index = (value >> 32).to_u32
    return nil if segment_index >= segments.size
    segment = segments[segment_index]

    # The pointer value pointed to by the far pointer is retrieved from that
    # particular byte offset within the target segment.
    pointer_value = segment.u64(byte_offset)

    # In the case of a double-far pointer, the pointer value is another far
    # pointer, pointing to the start of the content in another segment (rather
    # than pointing to a "landing pad" pointer as far pointers usually do).
    # We treat this as an override on the byte offset, which we fill here.
    override_byte_offset : UInt32 = 0xffffffff_u32
    if is_double_far
      # The landing pad of a double-far pointer is a normal far pointer.
      # We must validate it as such, then get from it the override byte offset.
      return nil if (pointer_value & 0b111_u64).to_u8 != 0b010_u8
      override_byte_offset = (pointer_value & 0xfffffff8_u64).to_u32

      # The second half of the landing pad of a double-far pointer is a
      # tag pointer value which is like a normal pointer to data,
      # except that its byte offset is always zero and is thus expected
      # to be overridden by the override byte offset gathered above.
      tag_pointer_value = segment.u64(byte_offset + 8)

      # We follow the second far pointer to the second target segment.
      segment_index = (pointer_value >> 32).to_u32
      segment = segments[segment_index]

      # And we treat the tag pointer value as the one that describes the data.
      pointer_value = tag_pointer_value
    end

    self.new(segment, byte_offset, override_byte_offset, pointer_value)
  end
end
