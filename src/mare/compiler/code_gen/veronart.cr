class Mare::Compiler::CodeGen::VeronaRT
  # Set to true only for debugging CodeGen of programs; otherwise, false.
  # TODO: Should this be configurable by a flag at runtime?
  USE_SYSTEMATIC_TESTING = true

  # The size by which every Cown object is padded with runtime-internal data.
  # We cheat the size smaller by point pointer here because we know the first
  # pointer is the type descriptor, which we still try not to touch directly,
  # except in cases where we are mimicking with non-runtime-allocated objects.
  COWN_PAD_SIZE = 8 * ((USE_SYSTEMATIC_TESTING ? 12 : 8) - 1) # TODO: cross-platform - not only the outer 8, but also the inner 12 and 8 are platform-dependent...

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

    # Verona runtime types.
    @alloc = llvm.struct_create_named("_.RTAlloc").as(LLVM::Type)
    @alloc_ptr = @alloc.pointer.as(LLVM::Type)
    @desc = llvm.struct_create_named("_.RTDescriptor").as(LLVM::Type)
    @desc_ptr = @desc.pointer.as(LLVM::Type)
    @obj_stack = llvm.struct_create_named("_.RTObjectStack").as(LLVM::Type)
    @obj_stack_ptr = @obj_stack.pointer.as(LLVM::Type)
    @obj = llvm.struct_create_named("_.RTObject").as(LLVM::Type)
    @obj_ptr = @obj.pointer.as(LLVM::Type)
    @cown = llvm.struct_create_named("_.RTCown").as(LLVM::Type)
    @cown_ptr = @cown.pointer.as(LLVM::Type)
    @cown_pad = @i8.array(COWN_PAD_SIZE).as(LLVM::Type)
    @main_inner_fn = LLVM::Type.function([@ptr], @void).as(LLVM::Type)
    @main_inner_fn_ptr = @main_inner_fn.pointer.as(LLVM::Type)
    @trace_fn = LLVM::Type.function([@obj_ptr, @obj_stack_ptr], @void).as(LLVM::Type)
    @trace_fn_ptr = @trace_fn.pointer.as(LLVM::Type)
    @final_fn = LLVM::Type.function([@obj_ptr], @void).as(LLVM::Type)
    @final_fn_ptr = @final_fn.pointer.as(LLVM::Type)
    @notify_fn = LLVM::Type.function([@obj_ptr], @void).as(LLVM::Type)
    @notify_fn_ptr = @notify_fn.pointer.as(LLVM::Type)
  end

  def gen_runtime_decls(g : CodeGen)
    align_width = 8_u64 # TODO: cross-platform
    [
      {"RTAlloc_get", [] of LLVM::Type, @alloc_ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::ReadNone,
      ]},
      {"RTCown_new", [@alloc_ptr, @desc_ptr], @cown_ptr, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::NoAlias},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Dereferenceable, align_width + COWN_PAD_SIZE},
        {LLVM::AttributeIndex::ReturnIndex, LLVM::Attribute::Alignment, align_width},
      ]},
      {"RTCown_release", [@cown_ptr, @alloc_ptr], @void, [
        LLVM::Attribute::NoUnwind, LLVM::Attribute::InaccessibleMemOrArgMemOnly,
      ]},
      {"RTSystematicTestHarness_run", [@i32, @pptr, @main_inner_fn_ptr, @ptr], @void,
        [] of LLVM::Attribute
      },
      {"puts", [@ptr], @i32, [] of LLVM::Attribute},
    ]
  end

  # TODO: Remove these when we can stop calling them from Mare programs.
  def gen_hacky_stubs(g)
    fn = g.mod.functions["pony_os_stdout"]
    g.gen_func_start(fn)
    g.builder.ret g.builder.bit_cast(@ptr.null, fn.return_type)
    g.gen_func_end

    fn = g.mod.functions["pony_os_stderr"]
    g.gen_func_start(fn)
    g.builder.ret g.builder.bit_cast(@ptr.null, fn.return_type)
    g.gen_func_end
  end

  def gen_alloc_ctx_get(g : CodeGen)
    g.builder.call(g.mod.functions["RTAlloc_get"], "ALLOC_CTX")
  end

  DESC_ID                    = 0
  DESC_TRACE_FN              = 1
  DESC_TRACE_POSSIBLY_ISO_FN = 2
  DESC_FINAL_FN              = 3
  DESC_NOTIFY_FN             = 4

  # This defines the generic LLVM struct type for what a type descriptor holds.
  # The type descriptor for each type uses a more specific version of this.
  # The order and sizes here must exactly match what is expected by the runtime,
  # and they should correlate to the constants above.
  def gen_desc_basetype
    @desc.struct_set_body [
      @isize,         # 0: size
      @trace_fn_ptr,  # 1: trace fn
      @trace_fn_ptr,  # 2: trace possibly iso fn
      @final_fn_ptr,  # 3: final fn
      @notify_fn_ptr, # 4: notified fn
      # TODO: id, traits bitmap, vtable
    ]
  end

  # This defines a more specific struct type than the above function,
  # tailored to the specific type definition and its virtual table size.
  # The actual type descriptor value for the type is an instance of this.
  def gen_desc_type(g : CodeGen, type_def : Reach::Def, vtable_size : Int32) : LLVM::Type
    g.llvm.struct [
      @isize,         # 0: size
      @trace_fn_ptr,  # 1: trace fn
      @trace_fn_ptr,  # 2: trace possibly iso fn
      @final_fn_ptr,  # 3: final fn
      @notify_fn_ptr, # 4: notified fn
      # TODO: id, traits bitmap, vtable
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

    trace_fn =
      if type_def.has_desc?
        g.mod.functions.add("#{type_def.llvm_name}.TRACE", @trace_fn)
      else
        @trace_fn_ptr.null
      end

    desc.initializer = gtype.desc_type.const_struct [
      @isize.const_int(abi_size), # 0: size
      trace_fn.to_value,          # 1: trace fn
      @trace_fn_ptr.null,         # 2: trace possibly iso fn TODO: @#{llvm_name}.TRACEPOSSIBLYISO
      @final_fn_ptr.null,         # 3: final fn TODO: @#{llvm_name}.FINAL
      @notify_fn_ptr.null,        # 4: notified fn TODO: @#{llvm_name}.NOTIFY
      # TODO: id, traits bitmap, vtable
    ]

    desc
  end

  def gen_vtable_gep_get(g, desc, name)
    raise NotImplementedError.new("Verona runtime: gen_vtable_gep_get")
  end

  def gen_traits_gep_get(g, desc, name)
    raise NotImplementedError.new("Verona runtime: gen_vtable_traits_get")
  end

  def gen_struct_type(g : CodeGen, gtype : GenType)
    elements = [] of LLVM::Type

    # All struct types start with the type descriptor (abbreviated "desc").
    # Even types with no desc have a singleton with a desc.
    # The values without a desc do not use this struct_type at all anyway.
    elements << gtype.desc_type.pointer

    # Different runtime objects have a different sized opaque pad at the start
    # that holds all of the runtime-internal data that we shouldn't touch.
    if gtype.type_def.is_actor?
      # Actors are cowns, and thus have a cown pad.
      elements << @cown_pad
    elsif !gtype.type_def.has_allocation? || gtype.type_def.is_abstract?
      # Objects that aren't runtime-allocated need no opaque pad at all,
      # because they don't need to hold any runtime-internal data.
      nil
    elsif gtype.type_def.llvm_name == "Env" \
      || gtype.type_def.llvm_name == "String" \
      || gtype.type_def.llvm_name.starts_with?("CPointer[")
      elements << @cown_pad
    else
      raise NotImplementedError.new("pad for #{gtype.type_def.llvm_name}")
    end

    # Each field of the type is an additional element in the struct type.
    gtype.fields.each { |name, t| elements << g.llvm_mem_type_of(t) }

    # The struct was previously opaque with no body. We now fill it in here.
    gtype.struct_type.struct_set_body(elements)
  end

  def gen_main(g : CodeGen)
    # Declare the inner main function that this one will eventually invoke.
    gen_main_inner(g)

    # Declare other temporary stubs needed for now.
    gen_hacky_stubs(g)

    # Declare the main function.
    main = g.mod.functions.add("main", [@i32, @pptr, @pptr], @i32)
    main.linkage = LLVM::Linkage::External

    g.gen_func_start(main)

    argc = main.params[0].tap &.name=("argc")
    argv = main.params[1].tap &.name=("argv")
    envp = main.params[2].tap &.name=("envp")

    # Get the current alloc_ctx and hold on to it.
    alloc_ctx = gen_alloc_ctx_get(g)
    g.func_frame.alloc_ctx = alloc_ctx

    # TODO: Create a singleton Env object to use here:
    env_obj = @ptr.null

    if USE_SYSTEMATIC_TESTING
      g.builder.call(g.mod.functions["RTSystematicTestHarness_run"], [
        argc,
        argv,
        g.mod.functions["main.INNER"].to_value,
        env_obj,
      ])
    else
      raise NotImplementedError.new("verona runtime init without test harness") # TODO
    end

    g.builder.ret(@i32.const_int(0)) # TODO: programs with a nonzero exit code

    g.gen_func_end
  end

  def gen_main_inner(g : CodeGen)
    fn = g.mod.functions.add("main.INNER", [@ptr], @void)
    arg = fn.params[0].tap &.name=("arg")

    g.gen_func_start(fn)

    # Create the main actor and become it.
    main_actor = g.gen_alloc_actor(g.gtypes["Main"], "main")

    g.builder.call(g.mod.functions["puts"], [
      g.gen_cstring("TODO: Send a message to the Main actor")
    ])

    g.builder.call(g.mod.functions["RTCown_release"], [
      g.builder.bit_cast(main_actor, @cown_ptr),
      g.alloc_ctx,
    ])

    g.builder.ret
    g.gen_func_end
  end

  def gen_alloc_actor(g : CodeGen, gtype : GenType, name)
    allocated = g.builder.call(g.mod.functions["RTCown_new"], [
      g.alloc_ctx,
      g.gen_get_desc_opaque(gtype),
    ], "#{name}.OPAQUE")
    g.builder.bit_cast(allocated, gtype.struct_ptr, name)
  end

  def gen_send_impl(g : CodeGen, gtype : GenType, gfunc : GenFunc)
    fn = gfunc.send_llvm_func
    g.gen_func_start(fn)

    # TODO: Send the message to the actor.

    g.builder.ret(g.gen_none)
    g.gen_func_end
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

    gtype.fields.each do |name, field_ref|
      # TODO: Trace the fields that need tracing.
    end

    g.builder.ret
    g.gen_func_end
  end

  def gen_dispatch_impl(g : CodeGen, gtype : GenType)
    # TODO: Does Verona need a dispatch implementation at all? Doesn't seem so.

    fn = g.mod.functions["#{gtype.type_def.llvm_name}.DISPATCH"]?
    return unless fn

    g.gen_func_start(fn)
    g.builder.ret
    g.gen_func_end
  end
end
