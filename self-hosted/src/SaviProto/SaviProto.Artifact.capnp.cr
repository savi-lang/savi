  ###
  # NOTE: This file was auto-generated from a Cap'n Proto file"
  # using the `capnp` compiler with the `--output=cr` option."


struct SaviProto::Artifact
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 1_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def name
    SaviProto::Artifact::Name.read_from_pointer(@p.struct(0))
  end

  def hash
    @p.u64(0x0)
  end
end

struct SaviProto::Artifact::Name
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 1_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def kind
    @p.text(0)
  end

  def is_package : Bool
    @p.check_union(0x0, 0)
  end
  def package!
    @p.assert_union!(0x0, 0)
    SaviProto::Artifact::Name::Package.read_from_pointer(@p.struct(1))
  end

  def is_source : Bool
    @p.check_union(0x0, 1)
  end
  def source!
    @p.assert_union!(0x0, 1)
    SaviProto::Artifact::Name::Source.read_from_pointer(@p.struct(1))
  end
end

struct SaviProto::Artifact::Name::Package
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def key
    @p.text(0)
  end

  def path
    @p.text(1)
  end
end

struct SaviProto::Artifact::Name::Source
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def package
    SaviProto::Artifact::Name::Package.read_from_pointer(@p.struct(0))
  end

  def key
    @p.text(1)
  end

  def path
    @p.text(2)
  end
end

struct SaviProto::Artifact::Invoke
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 1_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def id
    @p.u64(0x0)
  end

  def inputs
    CapnProto::List(SaviProto::Artifact).read_from_pointer(@p.list(0))
  end
end

struct SaviProto::Artifact::Invoke::Result
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 1_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def id
    @p.u64(0x0)
  end

  def outputs
    CapnProto::List(SaviProto::Artifact).read_from_pointer(@p.list(0))
  end

  def errors
    CapnProto::List(SaviProto::Source::Error).read_from_pointer(@p.list(1))
  end
end