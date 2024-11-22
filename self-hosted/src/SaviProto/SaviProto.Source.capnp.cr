  ###
  # NOTE: This file was auto-generated from a Cap'n Proto file"
  # using the `capnp` compiler with the `--output=cr` option."


struct SaviProto::Source
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 1_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def absolute_file_path
    @p.text(0)
  end

  def content_for_non_file
    @p.text(1)
  end

  def content_hash64
    @p.u64(0x0)
  end

  def package
    SaviProto::Source::Package.read_from_pointer(@p.struct(2))
  end
end

struct SaviProto::Source::Position
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def source
    SaviProto::Source.read_from_pointer(@p.struct(0))
  end

  def offset
    @p.u32(0x0)
  end

  def size
    @p.u32(0x4)
  end

  def row
    @p.u32(0x8)
  end

  def column
    @p.u32(0xc)
  end
end

struct SaviProto::Source::Package
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def absolute_manifest_directory_path
    @p.text(0)
  end

  def name
    @p.text(1)
  end
end

struct SaviProto::Source::Error
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def position
    SaviProto::Source::Position.read_from_pointer(@p.struct(0))
  end

  def message
    @p.text(1)
  end

  def extra_info
    CapnProto::List(SaviProto::Source::Error).read_from_pointer(@p.list(2))
  end
end