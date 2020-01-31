require "llvm"

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

class Mare::Compiler::CodeGen::PonyRT
  # From libponyrt/pony.h
  # Padding for actor types.
  #
  # 56 bytes: initial header, not including the type descriptor
  # 52/104 bytes: heap
  # 48/88 bytes: gc
  # 28/0 bytes: padding to 64 bytes, ignored
  ACTOR_PAD_SIZE = 248
  # TODO: adjust based on intptr size to account for 32-bit platforms:
  # if INTPTR_MAX == INT64_MAX
  #  define ACTOR_PAD_SIZE 248
  # elif INTPTR_MAX == INT32_MAX
  #  define ACTOR_PAD_SIZE 160
  # endif

  # From libponyrt/pony.h
  TRACE_MUTABLE = 0
  TRACE_IMMUTABLE = 1
  TRACE_OPAQUE = 2

  # From libponyrt/mem/pool.h
  POOL_MIN_BITS = 5
  POOL_MAX_BITS = 20
  POOL_ALIGN_BITS = 10
  POOL_MIN = (1 << POOL_MIN_BITS)
  POOL_MAX = (1 << POOL_MAX_BITS)

  # From libponyrt/mem/heap.h
  HEAP_MINBITS = 5
  HEAP_MAXBITS = (POOL_ALIGN_BITS - 1)
  HEAP_SIZECLASSES = (HEAP_MAXBITS - HEAP_MINBITS + 1)
  HEAP_MIN = (1_u64 << HEAP_MINBITS)
  HEAP_MAX = (1_u64 << HEAP_MAXBITS)

  # From libponyrt/mem/heap.c
  SIZECLASS_TABLE = [
    0, 1, 2, 2, 3, 3, 3, 3,
    4, 4, 4, 4, 4, 4, 4, 4,
  ]

  # From libponyrt/mem/heap.c
  def self.heap_index(size)
    SIZECLASS_TABLE[(size - 1) >> HEAP_MINBITS]
  end

  # From libponyrt/mem/pool.c
  # TODO: verify correctness of result compared to ponyc for various sizes
  def self.pool_index(size)
    # TODO: cross-platform (bits = 32 if platform is ilp32)
    bits = 64

    if size > POOL_MIN
      bits - clzl_64(size) - ((size & (size - 1)) ? 0 : 1)
    else
      0
    end
  end

  def self.clzl_64(x)
    # TODO: cross-platform (bits = 32 if platform is ilp32)
    bits = 64

    # TODO: verify correctness
    y = x >>32; (bits = bits -32; x = y) if y != 0
    y = x >>16; (bits = bits -16; x = y) if y != 0
    y = x >> 8; (bits = bits - 8; x = y) if y != 0
    y = x >> 4; (bits = bits - 4; x = y) if y != 0
    y = x >> 2; (bits = bits - 2; x = y) if y != 0
    y = x >> 1; return bits - 2 if y != 0
    return bits - x
  end

  getter desc
  getter obj

  def initialize(llvm : LLVM::Context, target_machine : LLVM::TargetMachine)
    # Standard types.
    @void     = llvm.void.as(LLVM::Type)
    @ptr      = llvm.int8.pointer.as(LLVM::Type)
    @pptr     = llvm.int8.pointer.pointer.as(LLVM::Type)
    @i1       = llvm.int1.as(LLVM::Type)
    @i1_false = llvm.int1.const_int(0).as(LLVM::Value)
    @i1_true  = llvm.int1.const_int(1).as(LLVM::Value)
    @i8       = llvm.int8.as(LLVM::Type)
    @i16      = llvm.int16.as(LLVM::Type)
    @i32      = llvm.int32.as(LLVM::Type)
    @i32_ptr  = llvm.int32.pointer.as(LLVM::Type)
    @i32_0    = llvm.int32.const_int(0).as(LLVM::Value)
    @i64      = llvm.int64.as(LLVM::Type)
    @isize    = llvm.intptr(target_machine.data_layout).as(LLVM::Type)
    @f32      = llvm.float.as(LLVM::Type)
    @f64      = llvm.double.as(LLVM::Type)

    # Pony runtime types.
    @desc = llvm.struct_create_named("_.DESC").as(LLVM::Type)
    @desc_ptr = @desc.pointer.as(LLVM::Type)
    @obj = llvm.struct_create_named("_.OBJECT").as(LLVM::Type)
    @obj_ptr = @obj.pointer.as(LLVM::Type)
    @actor_pad = @i8.array(ACTOR_PAD_SIZE).as(LLVM::Type)
    @msg = llvm.struct([@i32, @i32], "_.MESSAGE").as(LLVM::Type)
    @msg_ptr = @msg.pointer.as(LLVM::Type)
    @trace_fn = LLVM::Type.function([@ptr, @obj_ptr], @void).as(LLVM::Type)
    @trace_fn_ptr = @trace_fn.pointer.as(LLVM::Type)
    @serialise_fn = LLVM::Type.function([@ptr, @obj_ptr, @ptr, @ptr, @i32], @void).as(LLVM::Type) # TODO: fix 4th param type
    @serialise_fn_ptr = @serialise_fn.pointer.as(LLVM::Type)
    @deserialise_fn = LLVM::Type.function([@ptr, @obj_ptr], @void).as(LLVM::Type)
    @deserialise_fn_ptr = @deserialise_fn.pointer.as(LLVM::Type)
    @custom_serialise_space_fn = LLVM::Type.function([@obj_ptr], @i64).as(LLVM::Type)
    @custom_serialise_space_fn_ptr = @serialise_fn.pointer.as(LLVM::Type)
    @custom_deserialise_fn = LLVM::Type.function([@obj_ptr, @ptr], @void).as(LLVM::Type)
    @custom_deserialise_fn_ptr = @deserialise_fn.pointer.as(LLVM::Type)
    @dispatch_fn = LLVM::Type.function([@ptr, @obj_ptr, @msg_ptr], @void).as(LLVM::Type)
    @dispatch_fn_ptr = @dispatch_fn.pointer.as(LLVM::Type)
    @final_fn = LLVM::Type.function([@obj_ptr], @void).as(LLVM::Type)
    @final_fn_ptr = @final_fn.pointer.as(LLVM::Type)
  end

  def gen_runtime_decls(g : CodeGen)
    # Declare Pony runtime functions (and a few other functions we need).
    align_width = 8_u64 # TODO: cross-platform
    [
      {"pony_ctx", [] of LLVM::Type, @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::ReadNone,
      ]},
      {"pony_create", [@ptr, @desc_ptr], @obj_ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, align_width + ACTOR_PAD_SIZE},
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
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::DereferenceableOrNull, HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_small", [@ptr, @i32], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_large", [@ptr, @isize], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, HEAP_MAX << 1},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_realloc", [@ptr, @ptr, @isize], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::DereferenceableOrNull, HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_final", [@ptr, @isize], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::DereferenceableOrNull, HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_small_final", [@ptr, @i32], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, HEAP_MIN},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"pony_alloc_large_final", [@ptr, @isize], @ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, HEAP_MAX << 1},
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
    ]
  end

  def gen_alloc_ctx_get(g : CodeGen)
    g.builder.call(g.mod.functions["pony_ctx"], "ALLOC_CTX")
  end

  DESC_ID                        = 0
  DESC_SIZE                      = 1
  DESC_FIELD_COUNT               = 2
  DESC_FIELD_OFFSET              = 3
  DESC_INSTANCE                  = 4
  DESC_TRACE_FN                  = 5
  DESC_SERIALISE_TRACE_FN        = 6
  DESC_SERIALISE_FN              = 7
  DESC_DESERIALISE_FN            = 8
  DESC_CUSTOM_SERIALISE_SPACE_FN = 9
  DESC_CUSTOM_DESERIALISE_FN     = 10
  DESC_DISPATCH_FN               = 11
  DESC_FINAL_FN                  = 12
  DESC_EVENT_NOTIFY              = 13
  DESC_TRAITS                    = 14
  DESC_FIELDS                    = 15
  DESC_VTABLE                    = 16

  # This defines the generic LLVM struct type for what a type descriptor holds.
  # The type descriptor for each type uses a more specific version of this.
  # The order and sizes here must exactly match what is expected by the runtime,
  # and they should correlate to the constants above.
  def gen_desc_basetype
    @desc.struct_set_body [
      @i32,                           # 0: id
      @i32,                           # 1: size
      @i32,                           # 2: field_count
      @i32,                           # 3: field_offset
      @obj_ptr,                       # 4: instance
      @trace_fn_ptr,                  # 5: trace fn
      @trace_fn_ptr,                  # 6: serialise trace fn
      @serialise_fn_ptr,              # 7: serialise fn
      @deserialise_fn_ptr,            # 8: deserialise fn
      @custom_serialise_space_fn_ptr, # 9: custom serialise space fn
      @custom_deserialise_fn_ptr,     # 10: custom deserialise fn
      @dispatch_fn_ptr,               # 11: dispatch fn
      @final_fn_ptr,                  # 12: final fn
      @i32,                           # 13: event notify
      @isize.array(0).pointer,        # 14: traits bitmap
      @pptr,                          # 15: TODO: fields descriptors
      @ptr.array(0),                  # 16: vtable
    ]
  end

  # This defines a more specific struct type than the above function,
  # tailored to the specific type definition and its virtual table size.
  # The actual type descriptor value for the type is an instance of this.
  def gen_desc_type(g : CodeGen, type_def : Reach::Def, vtable_size : Int32) : LLVM::Type
    g.llvm.struct [
      @i32,                                      # 0: id
      @i32,                                      # 1: size
      @i32,                                      # 2: field_count
      @i32,                                      # 3: field_offset
      @obj_ptr,                                  # 4: instance
      @trace_fn_ptr,                             # 5: trace fn
      @trace_fn_ptr,                             # 6: serialise trace fn
      @serialise_fn_ptr,                         # 7: serialise fn
      @deserialise_fn_ptr,                       # 8: deserialise fn
      @custom_serialise_space_fn_ptr,            # 9: custom serialise space fn
      @custom_deserialise_fn_ptr,                # 10: custom deserialise fn
      @dispatch_fn_ptr,                          # 11: dispatch fn
      @final_fn_ptr,                             # 12: final fn
      @i32,                                      # 13: event notify
      @isize.array(g.trait_bitmap_size).pointer, # 14: traits bitmap
      @pptr,                                     # 15: TODO: fields descriptors
      @ptr.array(vtable_size),                   # 16: vtable
    ], "#{type_def.llvm_name}.DESC"
  end

  # This defines a global constant for the type descriptor of a type,
  # which is held as the first value in an object, used for identifying its
  # type at runtime, as well as a host of other functions related to dealing
  # with objects in the runtime, such as allocating them and tracing them.
  def gen_desc(g : CodeGen, gtype : GenType, vtable)
    type_def = gtype.type_def

    desc = g.mod.globals.add(gtype.desc_type, "#{type_def.llvm_name}.DESC")
    desc.linkage = LLVM::Linkage::LinkerPrivate
    desc.global_constant = true
    desc

    abi_size = g.abi_size_of(gtype.struct_type)
    field_offset =
      if gtype.fields.empty?
        0
      else
        g.target_machine.data_layout.offset_of_element(
          gtype.struct_type,
          gtype.field_index(gtype.fields[0][0]),
        )
      end

    dispatch_fn =
      if type_def.is_actor?
        g.mod.functions.add("#{type_def.llvm_name}.DISPATCH", @dispatch_fn)
      else
        @dispatch_fn_ptr.null
      end

    trace_fn =
      if type_def.has_desc? && gtype.fields.any?(&.last.trace_needed?)
        g.mod.functions.add("#{type_def.llvm_name}.TRACE", @trace_fn)
      else
        @trace_fn_ptr.null
      end

    # Generate a bitmap of one or more integers in which each bit represents
    # a trait in the program, with types that implement that trait having
    # the corresponding bit set in their version of the bitmap.
    # This is used for runtime type matching against abstract types (traits).
    is_asio_event_notify = false
    traits_bitmap = g.trait_bitmap_size.times.map { 0 }.to_a
    infer = g.ctx.infer[gtype.type_def.reified]
    g.ctx.reach.each_type_def.each do |other_def|
      if infer.is_subtype?(gtype.type_def.reified, other_def.reified)
        next if gtype.type_def == other_def
        raise "can't be subtype of a concrete" unless other_def.is_abstract?

        index = other_def.desc_id >> Math.log2(g.bitwidth).to_i
        raise "bad index or trait_bitmap_size" unless index < g.trait_bitmap_size

        bit = other_def.desc_id & (g.bitwidth - 1)
        traits_bitmap[index] |= (1 << bit)

        # Take special note if this type is a subtype of AsioEventNotify.
        is_asio_event_notify = true if other_def.llvm_name == "AsioEventNotify"
      end
    end
    traits_bitmap_global = g.gen_global_for_const \
      @isize.const_array(traits_bitmap.map { |bits| @isize.const_int(bits) })

    # If this type is an AsioEventNotify, then take note of the vtable index
    # of the _event_notify behaviour that the ASIO runtime will send to.
    # Otherwise, an index of -1 indicates that the runtime should *not* send.
    event_notify_vtable_index = @i32.const_int(
      is_asio_event_notify ? gtype["_event_notify"].vtable_index : -1
    )

    desc.initializer = gtype.desc_type.const_struct [
      @i32.const_int(type_def.desc_id),      # 0: id
      @i32.const_int(abi_size),              # 1: size
      @i32_0,                                # 2: TODO: field_count (tuples only)
      @i32.const_int(field_offset),          # 3: field_offset
      @obj_ptr.null,                         # 4: instance
      trace_fn.to_value,                     # 5: trace fn
      @trace_fn_ptr.null,                    # 6: serialise trace fn TODO: @#{llvm_name}.SERIALISETRACE
      @serialise_fn_ptr.null,                # 7: serialise fn TODO: @#{llvm_name}.SERIALISE
      @deserialise_fn_ptr.null,              # 8: deserialise fn TODO: @#{llvm_name}.DESERIALISE
      @custom_serialise_space_fn_ptr.null,   # 9: custom serialise space fn
      @custom_deserialise_fn_ptr.null,       # 10: custom deserialise fn
      dispatch_fn.to_value,                  # 11: dispatch fn
      @final_fn_ptr.null,                    # 12: final fn
      event_notify_vtable_index,             # 13: event notify TODO
      traits_bitmap_global,                  # 14: traits bitmap
      @pptr.null,                            # 15: TODO: fields
      @ptr.const_array(vtable),              # 16: vtable
    ]

    desc
  end

  def gen_vtable_gep_get(g, desc, name)
    g.builder.struct_gep(desc, DESC_VTABLE, name)
  end

  def gen_traits_gep_get(g, desc, name)
    g.builder.struct_gep(desc, DESC_TRAITS, name)
  end

  def gen_struct_type(g : CodeGen, gtype : GenType)
    elements = [] of LLVM::Type

    # All struct types start with the type descriptor (abbreviated "desc").
    # Even types with no desc have a singleton with a desc.
    # The values without a desc do not use this struct_type at all anyway.
    elements << gtype.desc_type.pointer

    # Actor types have an actor pad, which holds runtime internals containing
    # things like the message queue used to deliver runtime messages.
    elements << @actor_pad if gtype.type_def.has_actor_pad?

    # Each field of the type is an additional element in the struct type.
    gtype.fields.each { |name, t| elements << g.llvm_mem_type_of(t) }

    # The struct was previously opaque with no body. We now fill it in here.
    gtype.struct_type.struct_set_body(elements)
  end

  def gen_get_desc(g : CodeGen, value : LLVM::Value)
    desc_gep = g.builder.struct_gep(value, 0, "#{value.name}.DESC.GEP")
    g.builder.load(desc_gep, "#{value.name}.DESC")
  end

  def gen_main(g : CodeGen)
    # Declare the main function.
    main = g.mod.functions.add("main", [@i32, @pptr, @pptr], @i32)
    main.linkage = LLVM::Linkage::External

    g.gen_func_start(main)

    argc = main.params[0].tap &.name=("argc")
    argv = main.params[1].tap &.name=("argv")
    envp = main.params[2].tap &.name=("envp")

    # Call pony_init, letting it optionally consume some of the CLI args,
    # giving us a new value for argc and a mutated argv array.
    argc = g.builder.call(g.mod.functions["pony_init"], [@i32.const_int(1), argv], "argc")

    # Get the current alloc_ctx and hold on to it.
    alloc_ctx = gen_alloc_ctx_get(g)
    g.func_frame.alloc_ctx = alloc_ctx

    # Create the main actor and become it.
    main_actor = gen_alloc_actor(g, g.gtypes["Main"], "main", true)

    # TODO: Create the Env from argc, argv, and envp.
    env = gen_alloc(g, g.gtypes["Env"], nil, "env")
    g.builder.call(g.gtypes["Env"]["_create"].llvm_func, [env])
    # TODO: g.builder.call(g.gtypes["Env"]["_create"].llvm_func,
    #   [argc, g.builder.bit_cast(argv, @ptr), g.builder.bitcast(envp, @ptr)])

    # TODO: Run primitive initialisers using the main actor's heap.

    # Send the env in a message to the main actor's constructor
    g.builder.call(g.gtypes["Main"]["new"].send_llvm_func, [main_actor, env])

    # Start the runtime.
    start_success = g.builder.call(g.mod.functions["pony_start"], [
      @i1.const_int(0),
      @i32_ptr.null,
      @ptr.null, # TODO: pony_language_features_init_t*
    ], "start_success")

    # Branch based on the value of `start_success`.
    start_fail_block = g.gen_block("start_fail")
    post_block = g.gen_block("post")
    g.builder.cond(start_success, post_block, start_fail_block)

    # On failure, just write a failure message then continue to the post_block.
    g.builder.position_at_end(start_fail_block)
    g.builder.call(g.mod.functions["puts"], [
      g.gen_cstring("Error: couldn't start the runtime!")
    ])
    g.builder.br(post_block)

    # On success (or after running the failure block), do the following:
    g.builder.position_at_end(post_block)

    # TODO: Run primitive finalizers.

    # Become nothing (stop being the main actor).
    g.builder.call(g.mod.functions["pony_become"], [
      g.func_frame.alloc_ctx,
      @obj_ptr.null,
    ])

    # Get the program's chosen exit code (or 0 by default), but override
    # it with -1 if we failed to start the runtime.
    exitcode = g.builder.call(g.mod.functions["pony_get_exitcode"], "exitcode")
    ret = g.builder.select(start_success, exitcode, @i32.const_int(-1), "ret")
    g.builder.ret(ret)

    g.gen_func_end

    main
  end

  # We don't hook into gen_expr post hook at all - simply return the value.
  def gen_expr_post(g : CodeGen, expr : AST::Node, value : LLVM::Value)
    value
  end

  # This generates the code that allocates an object of the given type.
  # This is the first step before actually calling the constructor of it.
  def gen_alloc(g : CodeGen, gtype : GenType, _from_expr, name : String)
    object =
      if gtype.type_def.is_actor?
        gen_alloc_actor(g, gtype, name)
      else
        gen_alloc_struct(g, gtype.struct_type, name)
      end

    g.gen_put_desc(object, gtype, name)
    object
  end

  # This generates more generic code for allocating a given LLVM struct type,
  # without the assumption of it being initialized as a proper runtime object.
  def gen_alloc_struct(g : CodeGen, llvm_type : LLVM::Type, name)
    size = g.abi_size_of(llvm_type)
    size = 1 if size == 0
    args = [g.alloc_ctx]

    allocated =
      if size <= PonyRT::HEAP_MAX
        index = PonyRT.heap_index(size).to_i32
        args << @i32.const_int(index)
        # TODO: handle case where final_fn is present (pony_alloc_small_final)
        g.builder.call(g.mod.functions["pony_alloc_small"], args, "#{name}.MEM")
      else
        args << @isize.const_int(size)
        # TODO: handle case where final_fn is present (pony_alloc_large_final)
        g.builder.call(g.mod.functions["pony_alloc_large"], args, "#{name}.MEM")
      end

    g.builder.bit_cast(allocated, llvm_type.pointer, name)
  end

  # This generates the special kind of allocation needed by actors,
  # invoked by the above function when the type being allocated is an actor.
  def gen_alloc_actor(g : CodeGen, gtype : GenType, name, become_now = false)
    allocated = g.builder.call(g.mod.functions["pony_create"], [
      g.alloc_ctx,
      g.gen_get_desc_opaque(gtype),
    ], "#{name}.OPAQUE")

    if become_now
      g.builder.call(
        g.mod.functions["pony_become"],
        [g.gen_frame.alloc_ctx, allocated],
      )
    end

    g.builder.bit_cast(allocated, gtype.struct_ptr, name)
  end

  def gen_intrinsic_cpointer_alloc(g : CodeGen, params, llvm_type, elem_size_value)
    g.builder.bit_cast(
      g.builder.call(g.mod.functions["pony_alloc"], [
        g.alloc_ctx,
        g.builder.mul(params[0], @isize.const_int(elem_size_value)),
      ]),
      llvm_type,
    )
  end

  def gen_intrinsic_cpointer_realloc(g : CodeGen, params, llvm_type, elem_size_value)
    g.builder.bit_cast(
      g.builder.call(g.mod.functions["pony_realloc"], [
        g.alloc_ctx,
        g.builder.bit_cast(params[0], @ptr),
        g.builder.mul(params[1], @isize.const_int(elem_size_value)),
      ]),
      llvm_type,
    )
  end

  def gen_send_impl(g : CodeGen, gtype : GenType, gfunc : GenFunc)
    fn = gfunc.send_llvm_func
    g.gen_func_start(fn)

    # Get the message type and virtual table index to use.
    msg_type = gfunc.send_msg_llvm_type
    vtable_index = gfunc.vtable_index

    # Allocate a message object of the specific size/type used by this function.
    msg_size = g.abi_size_of(msg_type)
    pool_index = PonyRT.pool_index(msg_size)
    msg_opaque = g.builder.call(g.mod.functions["pony_alloc_msg"],
      [@i32.const_int(pool_index), @i32.const_int(vtable_index)], "msg.OPAQUE")
    msg = g.builder.bit_cast(msg_opaque, msg_type.pointer, "msg")

    src_types = [] of Reach::Ref
    dst_types = [] of Reach::Ref
    src_values = [] of LLVM::Value
    dst_values = [] of LLVM::Value
    needs_trace = false

    # Store all forwarding arguments in the message object.
    msg_type.struct_element_types.each_with_index do |elem_type, i|
      next if i < 3 # skip the first 3 boilerplate fields in the message
      param = fn.params[i - 3 + 1] # skip 3 fields, skip 1 param (the receiver)
      param.name = "param.#{i - 2}"

      arg = gfunc.func.params.not_nil!.terms[i - 3] # skip 3 fields
      dst_types << g.type_of(arg, gfunc)
      src_types << dst_types.last # TODO: are these ever different?

      needs_trace ||= src_types.last.trace_needed?(dst_types.last)

      # Cast the argument to the correct type and store it in the message.
      cast_arg = g.gen_assign_cast(param, elem_type, nil)
      arg_gep = g.builder.struct_gep(msg, i, "msg.#{i - 2}.GEP")
      g.builder.store(cast_arg, arg_gep)

      src_values << param
      dst_values << cast_arg
    end

    if needs_trace
      g.builder.call(g.mod.functions["pony_gc_send"], [g.alloc_ctx])

      src_values.each_with_index do |src_value, i|
        gen_trace(g, src_value, dst_values[i], src_types[i], dst_types[i])
      end

      g.builder.call(g.mod.functions["pony_send_done"], [g.alloc_ctx])
    end

    # If this is a constructor, we know that we are the only message producer
    # for this actor at this point, so we can optimize by using sendv_single.
    # Otherwise, we need to use the normal multi-producer-safe function.
    sendv_name =
      gfunc.func.has_tag?(:constructor) ? "pony_sendv_single" : "pony_sendv"

    # Send the message.
    g.builder.call(g.mod.functions[sendv_name], [
      g.alloc_ctx,
      g.builder.bit_cast(fn.params[0], @obj_ptr, "@.OPAQUE"),
      msg_opaque,
      msg_opaque,
      @i1.const_int(1)
    ])

    # Return None.
    g.builder.ret(g.gen_none)

    g.gen_func_end
  end

  def gen_desc_fn_impls(g : CodeGen, gtype : GenType)
    gen_dispatch_impl(g, gtype) if gtype.type_def.is_actor?
    gen_trace_impl(g, gtype)
  end

  def gen_trace_impl(g : CodeGen, gtype : GenType)
    raise "inconsistent frames" if g.frame_count > 1

    # Get the reference to the trace function declared earlier.
    # We'll fill in the implementation of that function now.
    fn = g.mod.functions["#{gtype.type_def.llvm_name}.TRACE"]?
    return unless fn

    fn.unnamed_addr = true
    fn.call_convention = LLVM::CallConvention::C
    fn.linkage = LLVM::Linkage::External

    g.gen_func_start(fn)

    fn.params[0].name = "PONY_CTX"
    fn.params[1].name = "@.OPAQUE"
    g.func_frame.alloc_ctx = fn.params[0]
    g.func_frame.receiver_value =
      g.builder.bit_cast(fn.params[1], gtype.struct_ptr, "@")

    if gtype.type_def.is_array?
      # We have a special-case implementation for Array (unfortunately).
      # This is the only case when we will trace "into" a CPointer.
      gen_trace_impl_for_array(g,gtype, fn)
    else
      # For all other types, we simply trace all fields (that need tracing).
      gtype.fields.each do |field_name, field_type|
        next unless field_type.trace_needed?

        field = g.gen_field_load(field_name, gtype)
        gen_trace(g, field, field, field_type, field_type)
      end
    end

    g.builder.ret
    g.gen_func_end
  end

  def gen_trace_impl_for_array(g : CodeGen, gtype : GenType, fn)
    elem_type_ref = gtype.type_def.array_type_arg
    array_size    = g.gen_field_load("_size", gtype)
    array_ptr     = g.gen_field_load("_ptr", gtype)

    # First, trace the base pointer itself.
    g.builder.call(g.mod.functions["pony_trace"], [
      g.alloc_ctx,
      g.builder.bit_cast(array_ptr, @ptr),
    ])

    # Now, we need to trace each of the array elements, one by one.
    # We do this by generating a crude loop over the array indexes.

    # Create a reassignable local variable-like alloca to hold the loop index.
    # TODO: Consider avoiding this how ponyc does, with a lazily-filled phi.
    index_alloca = g.builder.alloca(@isize, "ARRAY.TRACE.LOOP.INDEX.ALLOCA")
    g.builder.store(@isize.const_int(0), index_alloca)

    # Create some code blocks to use for the loop.
    cond_block = g.gen_block("ARRAY.TRACE.LOOP.COND")
    body_block = g.gen_block("ARRAY.TRACE.LOOP.BODY")
    post_block = g.gen_block("ARRAY.TRACE.LOOP.POST")

    # Start by jumping into the cond block.
    g.builder.br(cond_block)

    # In the cond block, compare the index variable to the array size,
    # jumping to the body block if still within bounds; else, the post block.
    g.builder.position_at_end(cond_block)
    index = g.builder.load(index_alloca, "ARRAY.TRACE.LOOP.INDEX")
    continue = g.builder.icmp(LLVM::IntPredicate::ULT, index, array_size)
    g.builder.cond(continue, body_block, post_block)

    # In the body block, get the element for this index and trace it.
    g.builder.position_at_end(body_block)
    elem =
      g.builder.load(
        g.builder.inbounds_gep(
          array_ptr,
          g.builder.load(index_alloca, "ARRAY.TRACE.LOOP.INDEX"),
          "ARRAY.TRACE.LOOP.ELEM.GEP",
        ),
        "ARRAY.TRACE.LOOP.ELEM",
      )
    gen_trace(g, elem, elem, elem_type_ref, elem_type_ref)

    # Then increment the index and continue to the next iteration of the loop.
    g.builder.store(
      g.builder.add(index, @isize.const_int(1)),
      index_alloca,
    )
    g.builder.br(cond_block)

    # Once done, move the builder to the post block for whatever code follows.
    g.builder.position_at_end(post_block)
  end

  def gen_dispatch_impl(g : CodeGen, gtype : GenType)
    raise "inconsistent frames" if g.frame_count > 1

    # Get the reference to the dispatch function declared earlier.
    # We'll fill in the implementation of that function now.
    fn = g.mod.functions["#{gtype.type_def.llvm_name}.DISPATCH"]
    fn.unnamed_addr = true
    fn.call_convention = LLVM::CallConvention::C
    fn.linkage = LLVM::Linkage::External

    g.gen_func_start(fn)

    fn.params[0].name = "PONY_CTX"
    fn.params[1].name = "@.OPAQUE"
    fn.params[2].name = "msg"

    g.func_frame.alloc_ctx = fn.params[0]
    receiver_opaque = fn.params[1]
    g.func_frame.receiver_value = receiver =
      g.builder.bit_cast(receiver_opaque, gtype.struct_ptr, "@")

    # Get the message id from the first field of the message object
    # (which was the third parameter to this function).
    msg_id_gep = g.builder.struct_gep(fn.params[2], 1, "msg.id.GEP")
    msg_id = g.builder.load(msg_id_gep, "msg.id")

    # Capture the current insert block so we can come back to it later,
    # after we jump around into each case block that we need to generate.
    orig_block = g.builder.insert_block

    # Generate the case block for each async function of this type,
    # mapped by the message id that corresponds to that function.
    cases = {} of LLVM::Value => LLVM::BasicBlock
    gtype.gfuncs.each do |func_name, gfunc|
      # Only look at functions with the async tag.
      next unless gfunc.func.has_tag?(:async)

      # Use the vtable index of the function as the message id to look for.
      id = @i32.const_int(gfunc.vtable_index)

      # Create the block to execute when the message id matches.
      cases[id] = block = g.gen_block("DISPATCH.#{func_name}")
      g.builder.position_at_end(block)

      src_types = [] of Reach::Ref
      dst_types = [] of Reach::Ref
      src_values = [] of LLVM::Value
      dst_values = [] of LLVM::Value
      needs_trace = false

      # Destructure args from the message.
      msg_type = gfunc.send_msg_llvm_type
      msg = g.builder.bit_cast(fn.params[2], msg_type.pointer, "msg.#{func_name}")
      msg_type.struct_element_types.each_with_index do |elem_type, i|
        next if i < 3 # skip the first 3 boilerplate fields in the message

        arg = gfunc.func.params.not_nil!.terms[i - 3] # skip 3 fields
        dst_types << g.type_of(arg, gfunc)
        src_types << dst_types.last # TODO: are these ever different?
        needs_trace ||= src_types.last.trace_needed?(dst_types.last)

        arg_gep = g.builder.struct_gep(msg, i, "msg.#{func_name}.#{i - 2}.GEP")
        src_value = g.builder.load(arg_gep, "msg.#{func_name}.#{i - 2}")
        src_values << src_value

        dst_value = g.gen_assign_cast(src_value, elem_type, nil)
        dst_values << dst_value
      end

      # Prepend the receiver as the first argument, not included in the message.
      args = [receiver] + dst_values

      if needs_trace
        g.builder.call(g.mod.functions["pony_gc_recv"], [g.alloc_ctx])

        src_values.each_with_index do |src_value, i|
          gen_trace(g, src_value, dst_values[i], src_types[i], dst_types[i])
        end

        g.builder.call(g.mod.functions["pony_recv_done"], [g.alloc_ctx])
      end

      # Call the underlying function and return void.
      g.builder.call(gfunc.llvm_func, args)
      g.builder.ret
    end

    # We rely on the typechecker to not let us call undefined async functions,
    # so the "else" case of this switch block is to be considered unreachable.
    unreachable_block = g.gen_block("unreachable_block")
    g.builder.position_at_end(unreachable_block)
    # TODO: LLVM infinite loop protection workaround (see gentype.c:503)
    g.builder.unreachable

    # Finally, return to the original block that we came from and create the
    # switch that maps onto all the case blocks that we just generated.
    g.builder.position_at_end(orig_block)
    g.builder.switch(msg_id, unreachable_block, cases)

    g.gen_func_end
  end

  def gen_trace_unknown(g : CodeGen, dst, ponyrt_trace_kind)
    g.builder.call(g.mod.functions["pony_traceunknown"], [
      g.alloc_ctx,
      g.builder.bit_cast(dst, @obj_ptr, "#{dst.name}.OPAQUE"),
      @i32.const_int(ponyrt_trace_kind),
    ])
  end

  def gen_trace_known(g : CodeGen, dst, src_type, ponyrt_trace_kind)
    src_gtype = g.gtype_of(src_type)

    g.builder.call(g.mod.functions["pony_traceknown"], [
      g.alloc_ctx,
      g.builder.bit_cast(dst, @obj_ptr, "#{dst.name}.OPAQUE"),
      g.builder.bit_cast(src_gtype.desc, @desc_ptr, "#{dst.name}.DESC"),
      @i32.const_int(ponyrt_trace_kind),
    ])
  end

  def gen_trace_dynamic(g : CodeGen, dst, src_type, dst_type, after_block)
    if src_type.is_union?
      src_type.union_children.each do |child_type|
        gen_trace_dynamic(g, dst, child_type, dst_type, after_block)
      end
      gen_trace_unknown(g, dst, PonyRT::TRACE_OPAQUE)
    elsif src_type.singular?
      src_type_def = src_type.single_def!(g.ctx)

      # We can't trace it if it doesn't have a descriptor,
      # and we shouldn't trace it if it isn't runtime-allocated.
      return unless src_type_def.has_desc? && src_type_def.has_allocation?

      # Generate code to check if this value is a subtype of this at runtime.
      is_subtype = g.gen_check_subtype_at_runtime(dst, src_type)
      true_block = g.gen_block("trace.is_subtype_of.#{src_type.show_type}")
      false_block = g.gen_block("trace.not_subtype_of.#{src_type.show_type}")
      g.builder.cond(is_subtype, true_block, false_block)

      # In the block in which the value was proved to indeed be a subtype,
      # Determine the mutability kind to use, then construct a newly refined
      # destination type to trace for, recursing/delegating back to gen_trace.
      g.builder.position_at_end(true_block)
      mutability = src_type.trace_mutability_of_nominal(
        g.ctx.infer[src_type_def.reified],
        dst_type,
      )
      refined_dst_type =
        case mutability
        when :mutable   then src_type_def.as_ref("iso")
        when :immutable then src_type_def.as_ref("val")
        when :opaque    then src_type_def.as_ref("tag")
        when :non       then src_type_def.as_ref("non")
        else
          raise NotImplementedError.new([src_type, dst_type])
        end
      gen_trace(g, dst, dst, src_type, refined_dst_type)

      # If we've traced as mutable or immutable, we're done with this element;
      # otherwise, we continue tracing as if the match had been false.
      case mutability
      when :mutable, :immutable then g.builder.br(after_block)
      else                           g.builder.br(false_block)
      end

      # Carry on to the next elements, continuing from the false block.
      g.builder.position_at_end(false_block)
    else
      raise NotImplementedError.new(src_type)
    end
  end

  def gen_trace(g : CodeGen, src : LLVM::Value, dst : LLVM::Value, src_type, dst_type)
    if src_type == dst_type
      trace_kind = src_type.trace_kind
    else
      trace_kind = src_type.trace_kind_with_dst_cap(dst_type.trace_kind)
    end

    case trace_kind
    when :machine_word
      if dst_type.trace_kind == :machine_word
        # Do nothing - no need to trace this value since it isn't boxed.
      else
        # The value is indeed boxed and has a type descriptor; trace it.
        gen_trace_known(g, dst, src_type, PonyRT::TRACE_IMMUTABLE)
      end
    when :mut_known
      gen_trace_known(g, dst, src_type, PonyRT::TRACE_MUTABLE)
    when :val_known, :non_known
      gen_trace_known(g, dst, src_type, PonyRT::TRACE_IMMUTABLE)
    when :tag_known
      gen_trace_known(g, dst, src_type, PonyRT::TRACE_OPAQUE)
    when :mut_unknown
      gen_trace_unknown(g, dst, PonyRT::TRACE_MUTABLE)
    when :val_unknown, :non_unknown
      gen_trace_unknown(g, dst, PonyRT::TRACE_IMMUTABLE)
    when :tag_unknown
      gen_trace_unknown(g, dst, PonyRT::TRACE_OPAQUE)
    when :static
      raise NotImplementedError.new("static") # TODO
    when :dynamic
      after_block = g.gen_block("after_dynamic_trace")
      gen_trace_dynamic(g, dst, src_type, dst_type, after_block)
      g.builder.br(after_block)
      g.builder.position_at_end(after_block)
    when :tuple
      raise NotImplementedError.new("tuple") # TODO
    else
      raise NotImplementedError.new(trace_kind)
    end
  end
end
