# This lib is necessary in order for us to link libponyrt with the mare binary,
# which is necessary in order for us to make `mare eval {{CODE}}` work right.
# If this dummy is not here, even if we include `--link-args=-lponyrt`
# in the crystal invocation, some part of the toolchain won't believe that
# we truly need to link the library and just leave it out of the `ldd` list.
# If the library is left out, we won't be able to access the Pony runtime
# functions from within out JIT-compiled `mare eval` execution.
@[Link("ponyrt")]
lib LibPonyRTDummy
  fun pony_get_exitcode() : Int32*
end
LibPonyRTDummy.pony_get_exitcode()

class Mare::Compiler::CodeGen
  def gen_runtime_decls
    # Declare Pony runtime functions (and a few other functions we need).
    align_width = 8_u64 # TODO: cross-platform
    [
      {"pony_ctx", [] of LLVM::Type, @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::ReadNone,
      ]},
      {"pony_create", [@ptr, @desc_ptr], @obj_ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, align_width + PonyRT::ACTOR_PAD_SIZE},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"ponyint_destroy", [@obj_ptr], @void, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
      ]},
      {"pony_sendv", [@ptr, @obj_ptr, @msg_ptr, @msg_ptr, @i1], @void, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
      ]},
      {"pony_sendv_single", [@ptr, @obj_ptr, @msg_ptr, @msg_ptr, @i1], @void, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
      ]},
      {"pony_alloc", [@ptr, @isize], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::DereferenceableOrNull, PonyRT::HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_small", [@ptr, @i32], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, PonyRT::HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_large", [@ptr, @isize], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, PonyRT::HEAP_MAX << 1},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_realloc", [@ptr, @ptr, @isize], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::DereferenceableOrNull, PonyRT::HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_final", [@ptr, @isize], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::DereferenceableOrNull, PonyRT::HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_small_final", [@ptr, @i32], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, PonyRT::HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_large_final", [@ptr, @isize], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, PonyRT::HEAP_MAX << 1},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_msg", [@i32, @i32], @msg_ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_trace", [@ptr, @ptr], @void, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {2, LLVM::Attribute::ReadNone},
      ]},
      {"pony_traceknown", [@ptr, @obj_ptr, @desc_ptr, @i32], @void, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {2, LLVM::Attribute::ReadOnly},
      ]},
      {"pony_traceunknown", [@ptr, @obj_ptr, @i32], @void, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {2, LLVM::Attribute::ReadOnly},
      ]},
      {"pony_gc_send", [@ptr], @void, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
      ]},
      {"pony_gc_recv", [@ptr], @void, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
      ]},
      {"pony_send_done", [@ptr], @void, [
        LLVM::Attribute::NoUnwind,
      ]},
      {"pony_recv_done", [@ptr], @void, [
        LLVM::Attribute::NoUnwind,
      ]},

      # TODO: pony_serialise_reserve
      # TODO: pony_serialise_offset
      # TODO: pony_deserialise_offset
      # TODO: pony_deserialise_block

      {"pony_init", [@i32, @pptr], @i32, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
      ]},
      {"pony_become", [@ptr, @obj_ptr], @void, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
      ]},
      {"pony_start", [@i1, @i32_ptr, @ptr], @i1, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
      ]},
      {"pony_get_exitcode", [] of LLVM::Type, @i32, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::ReadOnly,
      ]},
      {"pony_error", [] of LLVM::Type, @void, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::NoReturn,
      ]},

      # Internal Pony runtime functions that we will unscrupulously leverage.
      {"ponyint_next_pow2", [@isize], @isize, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::ReadNone,
      ]},
      {"ponyint_hash_block", [@ptr, @isize], @isize, [
        LLVM::Attribute::NoRecurse, LLVM::Attribute::NoUnwind,
        LLVM::Attribute::ReadOnly, LLVM::Attribute::UWTable,
        {1, LLVM::Attribute::ReadOnly},
      ]},

      # TODO: ponyint_personality_v0

      # Miscellaneous non-pony functions we depend on.
      {"puts", [@ptr], @i32, [] of LLVM::Attribute},
      {"memcmp", [@ptr, @ptr, @isize], @i32, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::ReadOnly,
        {1, LLVM::Attribute::ReadOnly},
        {2, LLVM::Attribute::ReadOnly},
      ]},
    ].each do |tuple|
      func = @mod.functions.add(tuple[0], tuple[1], tuple[2])
      tuple[3].each do |attr|
        if attr.is_a?(Tuple((LLVM::AttributeIndex | Int32), LLVM::Attribute))
          func.add_attribute(attr[1], attr[0])
        elsif attr.is_a?(Tuple((LLVM::AttributeIndex | Int32), LLVM::Attribute, UInt64))
          func.add_attribute(attr[1], attr[0], attr[2])
        else
          func.add_attribute(attr)
        end
      end
    end
  end
end
