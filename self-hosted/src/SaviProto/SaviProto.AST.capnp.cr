  ###
  # NOTE: This file was auto-generated from a Cap'n Proto file"
  # using the `capnp` compiler with the `--output=cr` option."


struct SaviProto::AST
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def position
    SaviProto::Source::Position.read_from_pointer(@p.struct(0))
  end

  def is_none : Bool
    @p.check_union(0x0, 0)
  end
  def none!
    @p.assert_union!(0x0, 0)
    nil
  end

  def is_character : Bool
    @p.check_union(0x0, 1)
  end
  def character!
    @p.assert_union!(0x0, 1)
    @p.u64(0x8)
  end

  def is_positive_integer : Bool
    @p.check_union(0x0, 2)
  end
  def positive_integer!
    @p.assert_union!(0x0, 2)
    @p.u64(0x8)
  end

  def is_negative_integer : Bool
    @p.check_union(0x0, 3)
  end
  def negative_integer!
    @p.assert_union!(0x0, 3)
    @p.u64(0x8)
  end

  def is_floating_point : Bool
    @p.check_union(0x0, 4)
  end
  def floating_point!
    @p.assert_union!(0x0, 4)
    @p.f64(0x8)
  end

  def is_name : Bool
    @p.check_union(0x0, 5)
  end
  def name!
    @p.assert_union!(0x0, 5)
    @p.text(1)
  end

  def is_string : Bool
    @p.check_union(0x0, 6)
  end
  def string!
    @p.assert_union!(0x0, 6)
    @p.text(1)
  end

  def is_string_with_prefix : Bool
    @p.check_union(0x0, 7)
  end
  def string_with_prefix!
    @p.assert_union!(0x0, 7)
    SaviProto::AST::AS_stringWithPrefix.read_from_pointer(@p)
  end

  def is_string_compose : Bool
    @p.check_union(0x0, 8)
  end
  def string_compose!
    @p.assert_union!(0x0, 8)
    SaviProto::AST::AS_stringCompose.read_from_pointer(@p)
  end

  def is_prefix : Bool
    @p.check_union(0x0, 9)
  end
  def prefix!
    @p.assert_union!(0x0, 9)
    SaviProto::AST::AS_prefix.read_from_pointer(@p)
  end

  def is_qualify : Bool
    @p.check_union(0x0, 10)
  end
  def qualify!
    @p.assert_union!(0x0, 10)
    SaviProto::AST::AS_qualify.read_from_pointer(@p)
  end

  def is_group : Bool
    @p.check_union(0x0, 11)
  end
  def group!
    @p.assert_union!(0x0, 11)
    SaviProto::AST::Group.read_from_pointer(@p.struct(1))
  end

  def is_relate : Bool
    @p.check_union(0x0, 12)
  end
  def relate!
    @p.assert_union!(0x0, 12)
    SaviProto::AST::AS_relate.read_from_pointer(@p)
  end

  def is_field_read : Bool
    @p.check_union(0x0, 13)
  end
  def field_read!
    @p.assert_union!(0x0, 13)
    SaviProto::AST::AS_fieldRead.read_from_pointer(@p)
  end

  def is_field_write : Bool
    @p.check_union(0x0, 14)
  end
  def field_write!
    @p.assert_union!(0x0, 14)
    SaviProto::AST::AS_fieldWrite.read_from_pointer(@p)
  end

  def is_field_displace : Bool
    @p.check_union(0x0, 15)
  end
  def field_displace!
    @p.assert_union!(0x0, 15)
    SaviProto::AST::AS_fieldDisplace.read_from_pointer(@p)
  end

  def is_call : Bool
    @p.check_union(0x0, 16)
  end
  def call!
    @p.assert_union!(0x0, 16)
    SaviProto::AST::Call.read_from_pointer(@p.struct(1))
  end

  def is_choice : Bool
    @p.check_union(0x0, 17)
  end
  def choice!
    @p.assert_union!(0x0, 17)
    SaviProto::AST::AS_choice.read_from_pointer(@p)
  end

  def is_loop : Bool
    @p.check_union(0x0, 18)
  end
  def loop!
    @p.assert_union!(0x0, 18)
    SaviProto::AST::Loop.read_from_pointer(@p.struct(1))
  end

  def is_try : Bool
    @p.check_union(0x0, 19)
  end
  def try!
    @p.assert_union!(0x0, 19)
    SaviProto::AST::Try.read_from_pointer(@p.struct(1))
  end

  def is_jump : Bool
    @p.check_union(0x0, 20)
  end
  def jump!
    @p.assert_union!(0x0, 20)
    SaviProto::AST::AS_jump.read_from_pointer(@p)
  end

  def is_yield : Bool
    @p.check_union(0x0, 21)
  end
  def yield!
    @p.assert_union!(0x0, 21)
    SaviProto::AST::AS_yield.read_from_pointer(@p)
  end
end

struct SaviProto::AST::AS_stringWithPrefix
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def prefix
    SaviProto::AST::Name.read_from_pointer(@p.struct(1))
  end

  def string
    @p.text(2)
  end
end

struct SaviProto::AST::AS_stringCompose
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def prefix
    SaviProto::AST::Name.read_from_pointer(@p.struct(1))
  end

  def terms
    CapnProto::List(SaviProto::AST).read_from_pointer(@p.list(2))
  end
end

struct SaviProto::AST::AS_prefix
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def op
    SaviProto::AST::Name.read_from_pointer(@p.struct(1))
  end

  def term
    SaviProto::AST.read_from_pointer(@p.struct(2))
  end
end

struct SaviProto::AST::AS_qualify
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def term
    SaviProto::AST.read_from_pointer(@p.struct(1))
  end

  def group
    SaviProto::AST::Group.read_from_pointer(@p.struct(2))
  end
end

struct SaviProto::AST::AS_relate
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def op
    SaviProto::AST::Name.read_from_pointer(@p.struct(1))
  end

  def terms
    SaviProto::AST::Pair.read_from_pointer(@p.struct(2))
  end
end

struct SaviProto::AST::AS_fieldRead
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def field
    @p.text(1)
  end
end

struct SaviProto::AST::AS_fieldWrite
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def field
    @p.text(1)
  end

  def value
    SaviProto::AST.read_from_pointer(@p.struct(2))
  end
end

struct SaviProto::AST::AS_fieldDisplace
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def field
    @p.text(1)
  end

  def value
    SaviProto::AST.read_from_pointer(@p.struct(2))
  end
end

struct SaviProto::AST::AS_choice
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def branches
    CapnProto::List(SaviProto::AST::ChoiceBranch).read_from_pointer(@p.list(1))
  end
end

struct SaviProto::AST::AS_jump
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def term
    SaviProto::AST.read_from_pointer(@p.struct(1))
  end

  def kind
    SaviProto::AST::JumpKind.new(@p.u16(4))
  end
end

struct SaviProto::AST::AS_yield
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 3_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def terms
    CapnProto::List(SaviProto::AST).read_from_pointer(@p.list(1))
  end
end

struct SaviProto::AST::Annotation
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 1_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def position
    SaviProto::Source::Position.read_from_pointer(@p.struct(0))
  end

  def target
    @p.u64(0x0)
  end

  def value
    @p.text(1)
  end
end

struct SaviProto::AST::Name
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def position
    SaviProto::Source::Position.read_from_pointer(@p.struct(0))
  end

  def value
    @p.text(1)
  end
end

struct SaviProto::AST::Pair
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

  def left
    SaviProto::AST.read_from_pointer(@p.struct(1))
  end

  def right
    SaviProto::AST.read_from_pointer(@p.struct(2))
  end
end

struct SaviProto::AST::Group
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 1_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def position
    SaviProto::Source::Position.read_from_pointer(@p.struct(0))
  end

  def style
    SaviProto::AST::Group::Style.new(@p.u16(0))
  end

  def terms
    CapnProto::List(SaviProto::AST).read_from_pointer(@p.list(1))
  end

  def has_exclamation
    @p.bool(0x2, 1)
  end
end

enum SaviProto::AST::Group::Style
  Root = 0
  Paren = 1
  Pipe = 2
  Square = 3
  Curly = 4
  Space = 5
end

struct SaviProto::AST::Call
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 4_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def receiver
    SaviProto::AST.read_from_pointer(@p.struct(0))
  end

  def name
    SaviProto::AST::Name.read_from_pointer(@p.struct(1))
  end

  def args
    CapnProto::List(SaviProto::AST).read_from_pointer(@p.list(2))
  end

  def yield
    SaviProto::AST::CallYield.read_from_pointer(@p.struct(3))
  end
end

struct SaviProto::AST::CallYield
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def params
    SaviProto::AST::Group.read_from_pointer(@p.struct(0))
  end

  def block
    SaviProto::AST::Group.read_from_pointer(@p.struct(1))
  end
end

struct SaviProto::AST::ChoiceBranch
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def cond
    SaviProto::AST.read_from_pointer(@p.struct(0))
  end

  def body
    SaviProto::AST.read_from_pointer(@p.struct(1))
  end
end

struct SaviProto::AST::Loop
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 4_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def initial_cond
    SaviProto::AST.read_from_pointer(@p.struct(0))
  end

  def body
    SaviProto::AST.read_from_pointer(@p.struct(1))
  end

  def repeat_cond
    SaviProto::AST.read_from_pointer(@p.struct(2))
  end

  def else_body
    SaviProto::AST.read_from_pointer(@p.struct(3))
  end
end

struct SaviProto::AST::Try
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 1_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def body
    SaviProto::AST.read_from_pointer(@p.struct(0))
  end

  def else_body
    SaviProto::AST.read_from_pointer(@p.struct(1))
  end

  def allow_non_partial_body
    @p.bool(0x0, 1)
  end
end

enum SaviProto::AST::JumpKind
  Error = 0
  Return = 1
  Break = 2
  Next = 3
end

struct SaviProto::AST::RawDeclare
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 4_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def terms
    CapnProto::List(SaviProto::AST).read_from_pointer(@p.list(0))
  end

  def main_annotation
    @p.text(1)
  end

  def body_annotations
    CapnProto::List(SaviProto::AST::Annotation).read_from_pointer(@p.list(2))
  end

  def body
    SaviProto::AST::Group.read_from_pointer(@p.struct(3))
  end
end

struct SaviProto::AST::RawDocument
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def source
    SaviProto::Source.read_from_pointer(@p.struct(0))
  end

  def declares
    CapnProto::List(SaviProto::AST::RawDeclare).read_from_pointer(@p.list(1))
  end
end

struct SaviProto::AST::Declare
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 6_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def name
    SaviProto::AST::Name.read_from_pointer(@p.struct(0))
  end

  def qualifier
    SaviProto::AST::Name.read_from_pointer(@p.struct(1))
  end

  def type_expr
    SaviProto::AST.read_from_pointer(@p.struct(2))
  end

  def params
    CapnProto::List(SaviProto::AST::Declare).read_from_pointer(@p.list(3))
  end

  def members
    CapnProto::List(SaviProto::AST::Declare).read_from_pointer(@p.list(4))
  end

  def attrs
    CapnProto::List(SaviProto::AST::Declare::Attr).read_from_pointer(@p.list(5))
  end
end

struct SaviProto::AST::Declare::Attr
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 2_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def name
    @p.text(0)
  end

  def is_tag : Bool
    @p.check_union(0x0, 0)
  end
  def tag!
    @p.assert_union!(0x0, 0)
    nil
  end

  def is_u64 : Bool
    @p.check_union(0x0, 1)
  end
  def u64!
    @p.assert_union!(0x0, 1)
    @p.u64(0x8)
  end

  def is_text : Bool
    @p.check_union(0x0, 2)
  end
  def text!
    @p.assert_union!(0x0, 2)
    @p.text(1)
  end
end

struct SaviProto::AST::Document
  def initialize(@p : CapnProto::Pointer::Struct)
  end
  private def self.new; end
  def self.read_from_pointer(p); obj = allocate; obj.initialize(p); obj; end

  CAPN_PROTO_DATA_WORD_COUNT = 0_u16
  CAPN_PROTO_POINTER_COUNT = 2_u16
  def capn_proto_address : UInt64; @p.capn_proto_address; end

  def source
    SaviProto::Source.read_from_pointer(@p.struct(0))
  end

  def declares
    CapnProto::List(SaviProto::AST::Declare).read_from_pointer(@p.list(1))
  end
end