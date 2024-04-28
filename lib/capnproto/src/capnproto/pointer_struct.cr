struct CapnProto::Pointer::Struct
  @segment : CapnProto::Segment
  @byte_offset : UInt32
  @data_word_count : UInt16
  @pointer_count : UInt16

  def initialize(@segment, @byte_offset, @data_word_count, @pointer_count)
  end

  def self.empty(segment)
    new(segment, 0, 0, 0)
  end

  def capn_proto_address
    @byte_offset.to_u64 | (@segment.index.to_u64 << 32)
  end

  def absolute_address
    @segment.bytes.to_unsafe.address + @byte_offset
  end

  private def ptr_byte_offset(n : UInt16) : UInt32?
    return nil if n >= @pointer_count
    @byte_offset + (@data_word_count + n).to_u32 * 8
  end

  def u8(n : UInt32) : UInt8
    return 0_u8 if n >= @data_word_count * 8
    @segment.u8(@byte_offset + n)
  end

  def u16(n : UInt32) : UInt16
    return 0_u16 if n >= @data_word_count * 8
    @segment.u16(@byte_offset + n)
  end

  def u32(n : UInt32) : UInt32
    return 0_u32 if n >= @data_word_count * 8
    @segment.u32(@byte_offset + n)
  end

  def u64(n : UInt32) : UInt64
    return 0_u64 if n >= @data_word_count * 8
    @segment.u64(@byte_offset + n)
  end

  def i8(n : UInt32) : Int8
    return u8(n).to_i8!
  end

  def i16(n : UInt32) : Int16
    return u16(n).to_i16!
  end

  def i32(n : UInt32) : Int32
    return u32(n).to_i32!
  end

  def i64(n : UInt32) : Int64
    return u64(n).to_i64!
  end

  def f32(n : UInt32) : Float32
    return 0.0_f32 if n >= @data_word_count * 8
    bytes = Bytes.new(
      @segment.bytes.to_unsafe + @byte_offset + n, 4, read_only: true
    )
    IO::ByteFormat::LittleEndian.decode(Float32, bytes)
  end

  def f64(n : UInt32) : Float64
    return 0.0_f64 if n >= @data_word_count * 8
    bytes = Bytes.new(
      @segment.bytes.to_unsafe + @byte_offset + n, 8, read_only: true
    )
    IO::ByteFormat::LittleEndian.decode(Float64, bytes)
  end

  def bool(n : UInt32, bit_mask : UInt8) : Bool
    u8(n) & bit_mask != 0
  end

  def u8_if_set(n : UInt32) : UInt8?
    return nil if n >= @data_word_count * 8
    value = @segment.u8(@byte_offset + n)
    value != 0 ? value : nil
  end

  def u16_if_set(n : UInt32) : UInt16?
    return nil if n >= @data_word_count * 8
    value = @segment.u16(@byte_offset + n)
    value != 0 ? value : nil
  end

  def u32_if_set(n : UInt32) : UInt32?
    return nil if n >= @data_word_count * 8
    value = @segment.u32(@byte_offset + n)
    value != 0 ? value : nil
  end

  def u64_if_set(n : UInt32) : UInt64?
    return nil if n >= @data_word_count * 8
    value = @segment.u64(@byte_offset + n)
    value != 0 ? value : nil
  end

  def i8_if_set(n : UInt32) : Int8?
    return u8_if_set(n).try(&.to_i8!)
  end

  def i16_if_set(n : UInt32) : Int16?
    return u16_if_set(n).try(&.to_i16!)
  end

  def i32_if_set(n : UInt32) : Int32?
    return u32_if_set(n).try(&.to_i32!)
  end

  def i64_if_set(n : UInt32) : Int64?
    return u64_if_set(n).try(&.to_i64!)
  end

  def f32_if_set(n : UInt32) : Float32?
    return nil if n >= @data_word_count * 8
    bytes = Bytes.new(
      @segment.bytes.to_unsafe + @byte_offset + n, 4, read_only: true
    )
    IO::ByteFormat::LittleEndian.decode(Float32, bytes)
  end

  def f64_if_set(n : UInt32) : Float64?
    return nil if n >= @data_word_count * 8
    bytes = Bytes.new(
      @segment.bytes.to_unsafe + @byte_offset + n, 8, read_only: true
    )
    IO::ByteFormat::LittleEndian.decode(Float64, bytes)
  end

  def bool_if_set(n : UInt32, bit_mask : UInt8) : Bool?
    byte = u8_if_set(n)
    byte.nil? ? nil : ((byte & bit_mask) != 0)
  end

  def assert_union!(n : UInt32, value : UInt16) : Nil
    raise ArgumentError.new("#{self} union at #{n} doesn't match #{value}") \
      if !check_union(n, value)
  end

  def check_union(n : UInt32, value : UInt16) : Bool
    u16(n) == value
  end

  def text_if_set(n : UInt16) : String?
    byte_offset = ptr_byte_offset(n)
    return nil if byte_offset.nil?
    CapnProto::Pointer::U8List.parse_from(
      @segment, byte_offset, @segment.u64(byte_offset)
    ).to_s
  end

  def text(n : UInt16) : String
    text_if_set(n) || ""
  end

  def data_if_set(n : UInt16) : Bytes?
    byte_offset = ptr_byte_offset(n)
    return nil if byte_offset.nil?
    CapnProto::Pointer::U8List.parse_from(
      @segment, byte_offset, @segment.u64(byte_offset)
    ).to_bytes
  end

  def data(n : UInt16) : Bytes
    data_if_set(n) || Bytes.new(0, read_only: true)
  end

  def struct_if_set(n : UInt16) : CapnProto::Pointer::Struct?
    byte_offset = ptr_byte_offset(n)
    return nil if byte_offset.nil?
    CapnProto::Pointer::Struct.parse_from(
      @segment, byte_offset, @segment.u64(byte_offset)
    )
  end

  def struct(n : UInt16) : CapnProto::Pointer::Struct
    struct_if_set(n) || CapnProto::Pointer::Struct.empty(@segment)
  end

  def list_if_set(n : UInt16) : CapnProto::Pointer::StructList?
    byte_offset = ptr_byte_offset(n)
    return nil if byte_offset.nil?
    CapnProto::Pointer::StructList.parse_from(
      @segment, byte_offset, @segment.u64(byte_offset)
    )
  end

  def list(n : UInt16) : CapnProto::Pointer::StructList
    list_if_set(n) || CapnProto::Pointer::StructList.empty(@segment)
  end

  def self.parse_from(
    segment : CapnProto::Segment,
    current_offset : UInt32,
    value : UInt64
  ) : CapnProto::Pointer::Struct
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

    # lsb                      struct pointer                       msb
    # +-+-----------------------------+---------------+---------------+
    # |A|             B               |       C       |       D       |
    # +-+-----------------------------+---------------+---------------+
    #
    # A (2 bits) = 0, to indicate that this is a struct pointer.
    # B (30 bits) = Offset, in words, from the end of the pointer to the
    #     start of the struct's data section.  Signed.
    # C (16 bits) = Size of the struct's data section, in words.
    # D (16 bits) = Size of the struct's pointer section, in words.

    # The 2 least significant bits (A) encode the pointer kind.
    # Return empty if this is not coded as a struct pointer (kind zero).
    return self.empty(segment) if (value & 0b11_u64).to_u8 != 0_u8

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
    lower_u32 = value.to_u32!
    offset_half = lower_u32.to_i32!
    byte_offset = (current_offset.to_i32 + 8 + offset_half + offset_half).to_u32
    if override_byte_offset != 0xffffffff_u32
      byte_offset = override_byte_offset
    end

    # The two upper U16 parts of the value (C and D) indicate the size
    # of the struct's data section and its pointers section, in 8-byte words.
    # These allow us to calculate the pointers section offset and end offset.
    data_word_count = (value >> 32).to_u16!
    pointer_count = (value >> 48).to_u16!

    self.new(segment, byte_offset, data_word_count, pointer_count)
  end
end
