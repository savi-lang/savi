  ###
  # NOTE: This file was auto-generated from a Cap'n Proto file"
  # using the `capnp` compiler with the `--output=cr` option."


struct CapnProto::Meta::Node
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 5_u16
  CAPN_PROTO_POINTER_COUNT = 6_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def id
    @p.u64(0x0)
  end

  def display_name
    @p.text(0)
  end

  def display_name_prefix_length
    @p.u32(0x8)
  end

  def scope_id
    @p.u64(0x10)
  end

  def nested_nodes
    CapnProto::List(CapnProto::Meta::Node::NestedNode).read_from_pointer(@p.list(1))
  end

  def annotations
    CapnProto::List(CapnProto::Meta::Annotation).read_from_pointer(@p.list(2))
  end

  def is_file : Bool
    @p.check_union(0xc, 0)
  end
  def file!
    @p.assert_union!(0xc, 0)
    nil
  end

  def is_struct : Bool
    @p.check_union(0xc, 1)
  end
  def struct!
    @p.assert_union!(0xc, 1)
    CapnProto::Meta::Node::AS_struct.read_from_pointer(@p)
  end

  def is_enum : Bool
    @p.check_union(0xc, 2)
  end
  def enum!
    @p.assert_union!(0xc, 2)
    CapnProto::Meta::Node::AS_enum.read_from_pointer(@p)
  end

  def is_interface : Bool
    @p.check_union(0xc, 3)
  end
  def interface!
    @p.assert_union!(0xc, 3)
    CapnProto::Meta::Node::AS_interface.read_from_pointer(@p)
  end

  def is_const : Bool
    @p.check_union(0xc, 4)
  end
  def const!
    @p.assert_union!(0xc, 4)
    CapnProto::Meta::Node::AS_const.read_from_pointer(@p)
  end

  def is_annotation : Bool
    @p.check_union(0xc, 5)
  end
  def annotation!
    @p.assert_union!(0xc, 5)
    CapnProto::Meta::Node::AS_annotation.read_from_pointer(@p)
  end

  def parameters
    CapnProto::List(CapnProto::Meta::Node::Parameter).read_from_pointer(@p.list(5))
  end

  def is_generic
    @p.bool(0x24, 1)
  end
end

struct CapnProto::Meta::Node::AS_struct
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 5_u16
  CAPN_PROTO_POINTER_COUNT = 6_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def data_word_count
    @p.u16(0xe)
  end

  def pointer_count
    @p.u16(0x18)
  end

  def preferred_list_encoding
    CapnProto::Meta::ElementSize.new(@p.u16(13))
  end

  def is_group
    @p.bool(0x1c, 1)
  end

  def discriminant_count
    @p.u16(0x1e)
  end

  def discriminant_offset
    @p.u32(0x20)
  end

  def fields
    CapnProto::List(CapnProto::Meta::Field).read_from_pointer(@p.list(3))
  end
end

struct CapnProto::Meta::Node::AS_enum
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 5_u16
  CAPN_PROTO_POINTER_COUNT = 6_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def enumerants
    CapnProto::List(CapnProto::Meta::Enumerant).read_from_pointer(@p.list(3))
  end
end

struct CapnProto::Meta::Node::AS_interface
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 5_u16
  CAPN_PROTO_POINTER_COUNT = 6_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def methods
    CapnProto::List(CapnProto::Meta::Method).read_from_pointer(@p.list(3))
  end

  def superclasses
    CapnProto::List(CapnProto::Meta::Superclass).read_from_pointer(@p.list(4))
  end
end

struct CapnProto::Meta::Node::AS_const
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 5_u16
  CAPN_PROTO_POINTER_COUNT = 6_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def type
    CapnProto::Meta::Type.read_from_pointer(@p.struct(3))
  end

  def value
    CapnProto::Meta::Value.read_from_pointer(@p.struct(4))
  end
end

struct CapnProto::Meta::Node::AS_annotation
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 5_u16
  CAPN_PROTO_POINTER_COUNT = 6_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def type
    CapnProto::Meta::Type.read_from_pointer(@p.struct(3))
  end

  def targets_file
    @p.bool(0xe, 1)
  end

  def targets_const
    @p.bool(0xe, 10)
  end

  def targets_enum
    @p.bool(0xe, 100)
  end

  def targets_enumerant
    @p.bool(0xe, 1000)
  end

  def targets_struct
    @p.bool(0xe, 10000)
  end

  def targets_field
    @p.bool(0xe, 100000)
  end

  def targets_union
    @p.bool(0xe, 1000000)
  end

  def targets_group
    @p.bool(0xe, 10000000)
  end

  def targets_interface
    @p.bool(0xf, 1)
  end

  def targets_method
    @p.bool(0xf, 10)
  end

  def targets_param
    @p.bool(0xf, 100)
  end

  def targets_annotation
    @p.bool(0xf, 1000)
  end
end

struct CapnProto::Meta::Node::Parameter
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def name
    @p.text(0)
  end
end

struct CapnProto::Meta::Node::NestedNode
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 1_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def name
    @p.text(0)
  end

  def id
    @p.u64(0x0)
  end
end

struct CapnProto::Meta::Field
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 4_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end
  NO_DISCRIMINANT = begin x : UInt16 = 65535; x; end

  def name
    @p.text(0)
  end

  def code_order
    @p.u16(0x0)
  end

  def annotations
    CapnProto::List(CapnProto::Meta::Annotation).read_from_pointer(@p.list(1))
  end

  def discriminant_value
    @p.u16(0x2) ^ 65535
  end

  def is_slot : Bool
    @p.check_union(0x8, 0)
  end
  def slot!
    @p.assert_union!(0x8, 0)
    CapnProto::Meta::Field::AS_slot.read_from_pointer(@p)
  end

  def is_group : Bool
    @p.check_union(0x8, 1)
  end
  def group!
    @p.assert_union!(0x8, 1)
    CapnProto::Meta::Field::AS_group.read_from_pointer(@p)
  end

  def ordinal
    CapnProto::Meta::Field::AS_ordinal.read_from_pointer(@p)
  end
end

struct CapnProto::Meta::Field::AS_slot
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 4_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def offset
    @p.u32(0x4)
  end

  def type
    CapnProto::Meta::Type.read_from_pointer(@p.struct(2))
  end

  def default_value
    CapnProto::Meta::Value.read_from_pointer(@p.struct(3))
  end

  def had_explicit_default
    @p.bool(0x10, 1)
  end
end

struct CapnProto::Meta::Field::AS_group
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 4_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def type_id
    @p.u64(0x10)
  end
end

struct CapnProto::Meta::Field::AS_ordinal
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 4_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def is_implicit : Bool
    @p.check_union(0xa, 0)
  end
  def implicit!
    @p.assert_union!(0xa, 0)
    nil
  end

  def is_explicit : Bool
    @p.check_union(0xa, 1)
  end
  def explicit!
    @p.assert_union!(0xa, 1)
    @p.u16(0xc)
  end
end

struct CapnProto::Meta::Enumerant
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 1_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def name
    @p.text(0)
  end

  def code_order
    @p.u16(0x0)
  end

  def annotations
    CapnProto::List(CapnProto::Meta::Annotation).read_from_pointer(@p.list(1))
  end
end

struct CapnProto::Meta::Superclass
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

  def brand
    CapnProto::Meta::Brand.read_from_pointer(@p.struct(0))
  end
end

struct CapnProto::Meta::Method
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 5_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def name
    @p.text(0)
  end

  def code_order
    @p.u16(0x0)
  end

  def param_struct_type
    @p.u64(0x8)
  end

  def result_struct_type
    @p.u64(0x10)
  end

  def annotations
    CapnProto::List(CapnProto::Meta::Annotation).read_from_pointer(@p.list(1))
  end

  def param_brand
    CapnProto::Meta::Brand.read_from_pointer(@p.struct(2))
  end

  def result_brand
    CapnProto::Meta::Brand.read_from_pointer(@p.struct(3))
  end

  def implicit_parameters
    CapnProto::List(CapnProto::Meta::Node::Parameter).read_from_pointer(@p.list(4))
  end
end

struct CapnProto::Meta::Type
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def is_void : Bool
    @p.check_union(0x0, 0)
  end
  def void!
    @p.assert_union!(0x0, 0)
    nil
  end

  def is_bool : Bool
    @p.check_union(0x0, 1)
  end
  def bool!
    @p.assert_union!(0x0, 1)
    nil
  end

  def is_int8 : Bool
    @p.check_union(0x0, 2)
  end
  def int8!
    @p.assert_union!(0x0, 2)
    nil
  end

  def is_int16 : Bool
    @p.check_union(0x0, 3)
  end
  def int16!
    @p.assert_union!(0x0, 3)
    nil
  end

  def is_int32 : Bool
    @p.check_union(0x0, 4)
  end
  def int32!
    @p.assert_union!(0x0, 4)
    nil
  end

  def is_int64 : Bool
    @p.check_union(0x0, 5)
  end
  def int64!
    @p.assert_union!(0x0, 5)
    nil
  end

  def is_uint8 : Bool
    @p.check_union(0x0, 6)
  end
  def uint8!
    @p.assert_union!(0x0, 6)
    nil
  end

  def is_uint16 : Bool
    @p.check_union(0x0, 7)
  end
  def uint16!
    @p.assert_union!(0x0, 7)
    nil
  end

  def is_uint32 : Bool
    @p.check_union(0x0, 8)
  end
  def uint32!
    @p.assert_union!(0x0, 8)
    nil
  end

  def is_uint64 : Bool
    @p.check_union(0x0, 9)
  end
  def uint64!
    @p.assert_union!(0x0, 9)
    nil
  end

  def is_float32 : Bool
    @p.check_union(0x0, 10)
  end
  def float32!
    @p.assert_union!(0x0, 10)
    nil
  end

  def is_float64 : Bool
    @p.check_union(0x0, 11)
  end
  def float64!
    @p.assert_union!(0x0, 11)
    nil
  end

  def is_text : Bool
    @p.check_union(0x0, 12)
  end
  def text!
    @p.assert_union!(0x0, 12)
    nil
  end

  def is_data : Bool
    @p.check_union(0x0, 13)
  end
  def data!
    @p.assert_union!(0x0, 13)
    nil
  end

  def is_list : Bool
    @p.check_union(0x0, 14)
  end
  def list!
    @p.assert_union!(0x0, 14)
    CapnProto::Meta::Type::AS_list.read_from_pointer(@p)
  end

  def is_enum : Bool
    @p.check_union(0x0, 15)
  end
  def enum!
    @p.assert_union!(0x0, 15)
    CapnProto::Meta::Type::AS_enum.read_from_pointer(@p)
  end

  def is_struct : Bool
    @p.check_union(0x0, 16)
  end
  def struct!
    @p.assert_union!(0x0, 16)
    CapnProto::Meta::Type::AS_struct.read_from_pointer(@p)
  end

  def is_interface : Bool
    @p.check_union(0x0, 17)
  end
  def interface!
    @p.assert_union!(0x0, 17)
    CapnProto::Meta::Type::AS_interface.read_from_pointer(@p)
  end

  def is_any_pointer : Bool
    @p.check_union(0x0, 18)
  end
  def any_pointer!
    @p.assert_union!(0x0, 18)
    CapnProto::Meta::Type::AS_anyPointer.read_from_pointer(@p)
  end
end

struct CapnProto::Meta::Type::AS_list
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def element_type
    CapnProto::Meta::Type.read_from_pointer(@p.struct(0))
  end
end

struct CapnProto::Meta::Type::AS_enum
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def type_id
    @p.u64(0x8)
  end

  def brand
    CapnProto::Meta::Brand.read_from_pointer(@p.struct(0))
  end
end

struct CapnProto::Meta::Type::AS_struct
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def type_id
    @p.u64(0x8)
  end

  def brand
    CapnProto::Meta::Brand.read_from_pointer(@p.struct(0))
  end
end

struct CapnProto::Meta::Type::AS_interface
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def type_id
    @p.u64(0x8)
  end

  def brand
    CapnProto::Meta::Brand.read_from_pointer(@p.struct(0))
  end
end

struct CapnProto::Meta::Type::AS_anyPointer
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def is_unconstrained : Bool
    @p.check_union(0x8, 0)
  end
  def unconstrained!
    @p.assert_union!(0x8, 0)
    CapnProto::Meta::Type::AS_anyPointer::AS_unconstrained.read_from_pointer(@p)
  end

  def is_parameter : Bool
    @p.check_union(0x8, 1)
  end
  def parameter!
    @p.assert_union!(0x8, 1)
    CapnProto::Meta::Type::AS_anyPointer::AS_parameter.read_from_pointer(@p)
  end

  def is_implicit_method_parameter : Bool
    @p.check_union(0x8, 2)
  end
  def implicit_method_parameter!
    @p.assert_union!(0x8, 2)
    CapnProto::Meta::Type::AS_anyPointer::AS_implicitMethodParameter.read_from_pointer(@p)
  end
end

struct CapnProto::Meta::Type::AS_anyPointer::AS_unconstrained
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def is_any_kind : Bool
    @p.check_union(0xa, 0)
  end
  def any_kind!
    @p.assert_union!(0xa, 0)
    nil
  end

  def is_struct : Bool
    @p.check_union(0xa, 1)
  end
  def struct!
    @p.assert_union!(0xa, 1)
    nil
  end

  def is_list : Bool
    @p.check_union(0xa, 2)
  end
  def list!
    @p.assert_union!(0xa, 2)
    nil
  end

  def is_capability : Bool
    @p.check_union(0xa, 3)
  end
  def capability!
    @p.assert_union!(0xa, 3)
    nil
  end
end

struct CapnProto::Meta::Type::AS_anyPointer::AS_parameter
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def scope_id
    @p.u64(0x10)
  end

  def parameter_index
    @p.u16(0xa)
  end
end

struct CapnProto::Meta::Type::AS_anyPointer::AS_implicitMethodParameter
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 3_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def parameter_index
    @p.u16(0xa)
  end
end

struct CapnProto::Meta::Brand
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def scopes
    CapnProto::List(CapnProto::Meta::Brand::Scope).read_from_pointer(@p.list(0))
  end
end

struct CapnProto::Meta::Brand::Scope
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def scope_id
    @p.u64(0x0)
  end

  def is_bind : Bool
    @p.check_union(0x8, 0)
  end
  def bind!
    @p.assert_union!(0x8, 0)
    CapnProto::List(CapnProto::Meta::Brand::Binding).read_from_pointer(@p.list(0))
  end

  def is_inherit : Bool
    @p.check_union(0x8, 1)
  end
  def inherit!
    @p.assert_union!(0x8, 1)
    nil
  end
end

struct CapnProto::Meta::Brand::Binding
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 1_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def is_unbound : Bool
    @p.check_union(0x0, 0)
  end
  def unbound!
    @p.assert_union!(0x0, 0)
    nil
  end

  def is_type : Bool
    @p.check_union(0x0, 1)
  end
  def type!
    @p.assert_union!(0x0, 1)
    CapnProto::Meta::Type.read_from_pointer(@p.struct(0))
  end
end

struct CapnProto::Meta::Value
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 1_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def is_void : Bool
    @p.check_union(0x0, 0)
  end
  def void!
    @p.assert_union!(0x0, 0)
    nil
  end

  def is_bool : Bool
    @p.check_union(0x0, 1)
  end
  def bool!
    @p.assert_union!(0x0, 1)
    @p.bool(0x2, 1)
  end

  def is_int8 : Bool
    @p.check_union(0x0, 2)
  end
  def int8!
    @p.assert_union!(0x0, 2)
    @p.i8(0x2)
  end

  def is_int16 : Bool
    @p.check_union(0x0, 3)
  end
  def int16!
    @p.assert_union!(0x0, 3)
    @p.i16(0x2)
  end

  def is_int32 : Bool
    @p.check_union(0x0, 4)
  end
  def int32!
    @p.assert_union!(0x0, 4)
    @p.i32(0x4)
  end

  def is_int64 : Bool
    @p.check_union(0x0, 5)
  end
  def int64!
    @p.assert_union!(0x0, 5)
    @p.i64(0x8)
  end

  def is_uint8 : Bool
    @p.check_union(0x0, 6)
  end
  def uint8!
    @p.assert_union!(0x0, 6)
    @p.u8(0x2)
  end

  def is_uint16 : Bool
    @p.check_union(0x0, 7)
  end
  def uint16!
    @p.assert_union!(0x0, 7)
    @p.u16(0x2)
  end

  def is_uint32 : Bool
    @p.check_union(0x0, 8)
  end
  def uint32!
    @p.assert_union!(0x0, 8)
    @p.u32(0x4)
  end

  def is_uint64 : Bool
    @p.check_union(0x0, 9)
  end
  def uint64!
    @p.assert_union!(0x0, 9)
    @p.u64(0x8)
  end

  def is_float32 : Bool
    @p.check_union(0x0, 10)
  end
  def float32!
    @p.assert_union!(0x0, 10)
    @p.f32(0x4)
  end

  def is_float64 : Bool
    @p.check_union(0x0, 11)
  end
  def float64!
    @p.assert_union!(0x0, 11)
    @p.f64(0x8)
  end

  def is_text : Bool
    @p.check_union(0x0, 12)
  end
  def text!
    @p.assert_union!(0x0, 12)
    @p.text(0)
  end

  def is_data : Bool
    @p.check_union(0x0, 13)
  end
  def data!
    @p.assert_union!(0x0, 13)
    @p.data(0)
  end

  def is_list : Bool
    @p.check_union(0x0, 14)
  end
  def list!
    @p.assert_union!(0x0, 14)
    nil # UNHANDLED: anyPointer
  end

  def is_enum : Bool
    @p.check_union(0x0, 15)
  end
  def enum!
    @p.assert_union!(0x0, 15)
    @p.u16(0x2)
  end

  def is_struct : Bool
    @p.check_union(0x0, 16)
  end
  def struct!
    @p.assert_union!(0x0, 16)
    nil # UNHANDLED: anyPointer
  end

  def is_interface : Bool
    @p.check_union(0x0, 17)
  end
  def interface!
    @p.assert_union!(0x0, 17)
    nil
  end

  def is_any_pointer : Bool
    @p.check_union(0x0, 18)
  end
  def any_pointer!
    @p.assert_union!(0x0, 18)
    nil # UNHANDLED: anyPointer
  end
end

struct CapnProto::Meta::Annotation
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

  def value
    CapnProto::Meta::Value.read_from_pointer(@p.struct(0))
  end

  def brand
    CapnProto::Meta::Brand.read_from_pointer(@p.struct(1))
  end
end

enum CapnProto::Meta::ElementSize
  Empty = 0
  Bit = 1
  Byte = 2
  TwoBytes = 3
  FourBytes = 4
  EightBytes = 5
  Pointer = 6
  InlineComposite = 7
end

struct CapnProto::Meta::CodeGeneratorRequest
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def nodes
    CapnProto::List(CapnProto::Meta::Node).read_from_pointer(@p.list(0))
  end

  def requested_files
    CapnProto::List(CapnProto::Meta::CodeGeneratorRequest::RequestedFile).read_from_pointer(@p.list(1))
  end
end

struct CapnProto::Meta::CodeGeneratorRequest::RequestedFile
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

  def filename
    @p.text(0)
  end

  def imports
    CapnProto::List(CapnProto::Meta::CodeGeneratorRequest::RequestedFile::Import).read_from_pointer(@p.list(1))
  end
end

struct CapnProto::Meta::CodeGeneratorRequest::RequestedFile::Import
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

  def name
    @p.text(0)
  end
end