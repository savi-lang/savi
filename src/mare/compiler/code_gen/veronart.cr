class Mare::Compiler::CodeGen::VeronaRT
  # Set to true only for debugging CodeGen of programs; otherwise, false.
  # TODO: Should this be configurable by a flag at runtime?
  USE_SYSTEMATIC_TESTING = true

  COWN_PAD_SIZE = 8 * (USE_SYSTEMATIC_TESTING ? 12 : 8) # TODO: cross-platform - not only the outer 8, but also the inner 12 and 8 are platform-dependent...

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
    @obj = llvm.struct_create_named("_.RTObject").as(LLVM::Type)
    @obj_ptr = @obj.pointer.as(LLVM::Type)
    @cown = llvm.struct_create_named("_.RTCown").as(LLVM::Type)
    @cown_ptr = @cown.pointer.as(LLVM::Type)
    @cown_pad = @i8.array(COWN_PAD_SIZE).as(LLVM::Type)
    @main_inner_fn = LLVM::Type.function([@ptr], @void).as(LLVM::Type)
    @main_inner_fn_ptr = @main_inner_fn.pointer.as(LLVM::Type)
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
      ]
      },
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

    g.builder.ret
    g.gen_func_end
  end

  def gen_alloc_actor(g : CodeGen, gtype : GenType, name)
    # allocated = g.builder.call(g.mod.functions["RTCown_new"], [
    #   g.alloc_ctx,
    #   g.gen_get_desc_opaque(gtype),
    # ], "#{name}.OPAQUE")
    # g.builder.bit_cast(allocated, gtype.struct_ptr, name)
    @ptr.null
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

    # TODO: Trace the value.

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
