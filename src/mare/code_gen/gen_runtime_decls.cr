class Mare::CodeGen
  def gen_runtime_decls
    # Declare Pony runtime functions (and a few other functions we need).
    align_width = 8_u64 # TODO: account for 32-bit platforms properly here
    [
      {"pony_ctx", [] of LLVM::Type, @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::ReadNone,
      ]},
      {"pony_create", [@ptr, @desc_ptr], @obj_ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, align_width + PONYRT_ACTOR_PAD_SIZE},
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
      {"pony_alloc", [@ptr, @intptr], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::DereferenceableOrNull, PONYRT_HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_small", [@ptr, @i32], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, PONYRT_HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_large", [@ptr, @intptr], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, PONYRT_HEAP_MAX << 1},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_realloc", [@ptr, @ptr, @intptr], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::DereferenceableOrNull, PONYRT_HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_final", [@ptr, @intptr], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::DereferenceableOrNull, PONYRT_HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_small_final", [@ptr, @i32], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, PONYRT_HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_large_final", [@ptr, @intptr], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, PONYRT_HEAP_MAX << 1},
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
      
      # TODO: ponyint_personality_v0
      
      # Miscellaneous non-pony functions we depend on.
      {"puts", [@ptr], @i32, [] of LLVM::Attribute},
      {"memcmp", [@ptr, @ptr, @intptr], @i32, [
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
