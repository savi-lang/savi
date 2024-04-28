class CapnProto::Segment
  getter segments : Array(CapnProto::Segment)
  getter index : UInt32 # index of this segment in the @segments array
  getter bytes : Bytes

  def initialize(segments : Array(CapnProto::Segment), bytes : Bytes)
    @bytes = bytes
    @segments = segments
    @index = @segments.size.to_u32
    @segments << self
  end

  def u8(offset : UInt32) : UInt8
    @bytes[offset]
  end

  def u16(offset : UInt32) : UInt16
    @bytes[offset].to_u16 \
    | (@bytes[offset + 1].to_u16 << 8)
  end

  def u32(offset : UInt32) : UInt32
    @bytes[offset].to_u32 \
    | (@bytes[offset + 1].to_u32 << 8) \
    | (@bytes[offset + 2].to_u32 << 16) \
    | (@bytes[offset + 3].to_u32 << 24)
  end

  def u64(offset : UInt32) : UInt64
    @bytes[offset].to_u64 \
    | (@bytes[offset + 1].to_u64 << 8) \
    | (@bytes[offset + 2].to_u64 << 16) \
    | (@bytes[offset + 3].to_u64 << 24) \
    | (@bytes[offset + 4].to_u64 << 32) \
    | (@bytes[offset + 5].to_u64 << 40) \
    | (@bytes[offset + 6].to_u64 << 48) \
    | (@bytes[offset + 7].to_u64 << 56)
  end
end

class CapnProto::Segment::Reader
  def initialize(
    # The maximum total size that the segment buffers are allowed to allocate.
    #
    # This security limit should be configured to a size that is large enough
    # for any legitimate application messages, but small enough so as to not
    # allow attackers to cause out-of-memory errors by announcing large sizes.
    @max_total_size : UInt64 = 0x4000000 # 64 MiB
  )
    @segments = [] of CapnProto::Segment
    @header = Bytes.new(0)
    @next_segment_bytes = Bytes.new(0)
  end

  def read(io : IO)
    return nil if !maybe_read_header(io)
    return nil if !maybe_read_all_segments(io)
    @segments
  end

  private def read_at_most_n_bytes_from(io : IO, size : UInt32) : Bytes
    bytes = Bytes.new(size)
    actual_size = io.read(bytes)
    Bytes.new(bytes.to_unsafe, actual_size, read_only: true)
  end

  private def header_u32(offset : UInt32) : UInt32
    @header[offset].to_u32 \
    | (@header[offset + 1].to_u32 << 8) \
    | (@header[offset + 2].to_u32 << 16) \
    | (@header[offset + 3].to_u32 << 24)
  end

  private def expected_segment_count
    header_u32(0) + 1
  end

  private def expected_segment_size(i : UInt32) : UInt32
    header_u32((i + 1) * 4) * 8
  end

  private def expected_total_size_for_segments : UInt32
    total : UInt32 = 0
    expected_segment_count.times do |i|
      total += expected_segment_size(i)
    end
    total
  end

  private def maybe_read_header(io : IO) : Bool
    # Determine the number of segments that will be in the segment table.
    # Return false if there aren't enough bytes yet to read the first U32.
    if @header.size < 4
      @header += read_at_most_n_bytes_from(io, 4_u32 - @header.size)
      if @header.size < 4
        return false
      end
    end
    segment_count = expected_segment_count

    # Determine the number of bytes to expect in the segment table header.
    # Raise an error if even the header alone will exceed our max size.
    header_has_padding = (segment_count % 2) == 0
    header_size = ((segment_count + 1) * 4) + (header_has_padding ? 4 : 0)
    if header_size > @max_total_size
      raise ArgumentError.new(
        "Segment table header size (#{header_size} bytes) exceeds " \
        "max total size (#{@max_total_size} bytes)"
      )
    end

    # Extract the header bytes into our field for storage later.
    # Return false if the complete header bytes aren't available yet.
    if @header.size < header_size
      @header += read_at_most_n_bytes_from(io, header_size - @header.size)
      if @header.size < header_size
        return false
      end
    end

    # Now that we have the header, we can calculate the expected total size.
    # Raise an error if the size would violate our security limit.
    expected_total_size_for_all = expected_total_size_for_segments + header_size
    if expected_total_size_for_segments + header_size > @max_total_size
      raise ArgumentError.new(
        "Segment table size (#{expected_total_size_for_all} bytes) " \
        "exceeds max total size (#{@max_total_size} bytes)"
      )
    end

    true
  end

  private def maybe_read_all_segments(io : IO)
    while @segments.size < expected_segment_count
      segment_size = expected_segment_size(@segments.size.to_u32)
      @next_segment_bytes += read_at_most_n_bytes_from(io,
        segment_size - @next_segment_bytes.size
      )

      if @next_segment_bytes.size < segment_size
        return false
      end

      CapnProto::Segment.new(@segments, Bytes.new(
        @next_segment_bytes.to_unsafe,
        @next_segment_bytes.size,
        read_only: true
      ))
      @next_segment_bytes = Bytes.new(0)
    end

    true
  end
end