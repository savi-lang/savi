require "llvm"
require "random"
require "../ext/llvm" # TODO: get these merged into crystal standard library
require "./code_gen/*"

##
# The purpose of the CodeGen pass is to generate LLVM code (IR) which can
# be used along with LLVM tooling to create an executable program.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps state at the program level.
# This pass produces output state at the program level.
#
class Savi::Compiler::CodeGen
  getter llvm : LLVM::Context
  getter target : LLVM::Target
  getter target_machine : LLVM::TargetMachine
  getter target_info : Target
  getter mod : LLVM::Module
  getter builder : LLVM::Builder

  def self.recursively_contains_direct_struct_type?(check_type : LLVM::Type, look_for_type : LLVM::Type) : Bool
    return false unless check_type.kind == LLVM::Type::Kind::Struct
    return true if check_type == look_for_type
    check_type.struct_element_types.any? do |t|
      recursively_contains_direct_struct_type?(t, look_for_type)
    end
  end

  class Frame
    getter! llvm_func : LLVM::Function?
    getter gtype : GenType?
    getter gfunc : GenFunc?

    setter alloc_ctx : LLVM::Value?
    property! receiver_value : LLVM::Value?
    property! continuation_value : LLVM::Value

    getter current_locals
    getter yielding_call_conts
    getter yielding_call_receivers

    def initialize(@g : CodeGen, @llvm_func = nil, @gtype = nil, @gfunc = nil)
      @current_locals = {} of Refer::Local => LLVM::Value
      @yielding_call_conts = {} of AST::Call => LLVM::Value
      @yielding_call_receivers = {} of AST::Call => LLVM::Value
    end

    def alloc_ctx?
      @alloc_ctx.is_a?(LLVM::Value)
    end

    def alloc_ctx
      @alloc_ctx.as(LLVM::Value)
    end

    def refer
      @g.ctx.refer[@gfunc.as(GenFunc).link]
    end

    def classify
      @g.ctx.classify[@gfunc.as(GenFunc).link]
    end

    def flow
      @g.ctx.flow[@gfunc.as(GenFunc).link]
    end

    def local
      @g.ctx.local[@gfunc.as(GenFunc).link]
    end

    def any_defn_for_local(ref : Refer::Info)
      local.any_initial_site_for(ref).node
    end

    @entry_block : LLVM::BasicBlock?
    def entry_block
      @entry_block ||= llvm_func.basic_blocks.append("entry")
      @entry_block.not_nil!
    end
  end

  getter! ctx : Context

  getter llvm
  getter mod
  getter builder
  getter di
  getter gtypes
  getter bitwidth
  getter isize

  def initialize(
    runtime : PonyRT.class | VeronaRT.class,
    options : Compiler::Options
  )
    LLVM.init_x86
    LLVM.init_aarch64
    LLVM.init_arm
    @target_triple = (
      options.cross_compile || LLVM.configured_default_target_triple
    ).as(String)
    @target = LLVM::Target.from_triple(@target_triple)
    @target_machine = @target.create_target_machine(@target_triple).as(LLVM::TargetMachine)
    @target_info = Target.new(@target_machine.triple)
    @llvm = LLVM::Context.new

    @mod = @llvm.new_module("main")
    @builder = @llvm.new_builder

    @runtime = runtime.new(@llvm, @target_machine).as(PonyRT | VeronaRT)
    @di = DebugInfo.new(@llvm, @mod, @builder, @target_machine.data_layout, @runtime)

    @default_linkage = LLVM::Linkage::External

    @void     = @llvm.void.as(LLVM::Type)
    @ptr      = @llvm.int8.pointer.as(LLVM::Type)
    @pptr     = @llvm.int8.pointer.pointer.as(LLVM::Type)
    @i1       = @llvm.int1.as(LLVM::Type)
    @i1_false = @llvm.int1.const_int(0).as(LLVM::Value)
    @i1_true  = @llvm.int1.const_int(1).as(LLVM::Value)
    @i8       = @llvm.int8.as(LLVM::Type)
    @i16      = @llvm.int16.as(LLVM::Type)
    @i32      = @llvm.int32.as(LLVM::Type)
    @i32_ptr  = @llvm.int32.pointer.as(LLVM::Type)
    @i32_0    = @llvm.int32.const_int(0).as(LLVM::Value)
    @i64      = @llvm.int64.as(LLVM::Type)
    @i128     = @llvm.int128.as(LLVM::Type)
    @isize    = @llvm.intptr(@target_machine.data_layout).as(LLVM::Type)
    @f32      = @llvm.float.as(LLVM::Type)
    @f64      = @llvm.double.as(LLVM::Type)

    @pony_error_landing_pad_type =
      @llvm.struct([@ptr, @i32], "_.PONY_ERROR_LANDING_PAD_TYPE").as(LLVM::Type)
    @pony_error_personality_fn = @mod.functions.add("ponyint_personality_v0",
      [] of LLVM::Type, @i32).as(LLVM::Function)

    @bitwidth = @isize.int_width.to_u.as(UInt32)
    @memcpy = mod.functions.add("llvm.memcpy.p0.p0.i#{@bitwidth}",
      [@ptr, @ptr, @isize, @i1], @void).as(LLVM::Function)

    @frames = [] of Frame
    @cstring_globals = {} of String => LLVM::Value
    @string_globals = {} of String => LLVM::Value
    @bstring_globals = {} of String => LLVM::Value
    @source_code_pos_globals = {} of Source::Pos => LLVM::Value
    @reflection_of_type_globals = {} of GenType => LLVM::Value
    @gtypes = {} of String => GenType
    @loop_next_stack = Array(Tuple(
      LLVM::BasicBlock, Array(LLVM::BasicBlock), Array(LLVM::Value), Reach::Ref,
    )).new
    @loop_break_stack = Array(Tuple(
      LLVM::BasicBlock, Array(LLVM::BasicBlock), Array(LLVM::Value), Reach::Ref
    )).new

    @try_else_stack = Array(Tuple(
      LLVM::BasicBlock, Array(LLVM::BasicBlock), Array(LLVM::Value)
    )).new

    @value_not_needed = @llvm.struct([@i1], "_.VALUE_NOT_NEEDED").as(LLVM::Type)

    # Pony runtime types.
    # TODO: Remove these, because they're already present in PonyRT
    @desc = @runtime.desc.as(LLVM::Type)
    @desc_ptr = @desc.pointer.as(LLVM::Type)
    @obj = @runtime.obj.as(LLVM::Type)
    @obj_ptr = @obj.pointer.as(LLVM::Type)
    @actor_pad = @i8.array(PonyRT::ACTOR_PAD_SIZE).as(LLVM::Type)
    @msg = @llvm.struct([@i32, @i32], "_.MESSAGE").as(LLVM::Type)
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

    # Finish defining the forward-declared @desc and @obj types
    @runtime.gen_desc_basetype
    @obj.struct_set_body([@desc_ptr])

    @runtime.gen_runtime_decls(self).each do |tuple|
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

  def gtype_main
    main_gtype = @gtypes["Main"]?

    unless main_gtype
      Error.at Source::Pos.none, "This package has no Main actor"
    end

    main_gtype.not_nil!
  end

  def frame_count
    @frames.size
  end

  def frame
    @frames.last
  end

  def func_frame
    @frames.reverse_each.find { |f| f.llvm_func? }.not_nil!
  end

  def gen_frame
    @frames.each.find { |f| f.llvm_func? }.not_nil!
  end

  def finish_block
    old_block = @builder.insert_block
    if old_block
      old_block.get_terminator || @builder.unreachable
    end
  end

  def finish_block_and_move_to(new_block)
    finish_block
    @builder.position_at_end(new_block)
  end

  def abi_size_of(llvm_type : LLVM::Type)
    @target_machine.data_layout.abi_size(llvm_type)
  end

  def meta_type_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    in_gfunc ||= func_frame.gfunc.not_nil!
    in_gfunc.reified.meta_type_of(ctx, expr, in_gfunc.infer)
  end

  def meta_type_unconstrained?(expr : AST::Node, in_gfunc : GenFunc? = nil)
    in_gfunc ||= func_frame.gfunc.not_nil!
    # TODO: Simplify the following circuitous/unoptimized code
    info = ctx.pre_infer[in_gfunc.link][expr]
    return true if ctx.subtyping.for_rf(in_gfunc.reified).ignores_layer?(ctx, info.layer_index)

    mt = in_gfunc.reified.meta_type_of(ctx, expr, in_gfunc.infer)
    return true unless mt

    mt.unconstrained?
  end

  def type_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    ctx.reach[meta_type_of(expr, in_gfunc).not_nil!]
  end

  def type_of_unless_unsatisfiable(expr : AST::Node, in_gfunc : GenFunc? = nil)
    mt = meta_type_of(expr, in_gfunc).not_nil!
    ctx.reach[mt] unless mt.unsatisfiable?
  end

  def llvm_type_of(gtype : GenType)
    llvm_type_of(gtype.type_def.as_ref) # TODO: this is backwards - defs should have a llvm_use_type of their own, with refs delegating to that implementation when there is a singular meta_type
  end

  def llvm_type_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    llvm_type_of(type_of(expr, in_gfunc))
  end

  def llvm_mem_type_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    llvm_mem_type_of(type_of(expr, in_gfunc))
  end

  def llvm_type_of(ref : Reach::Ref)
    case ref.llvm_use_type(ctx)
    when :i1 then @i1
    when :i8 then @i8
    when :i16 then @i16
    when :i32 then @i32
    when :i64 then @i64
    when :f32 then @f32
    when :f64 then @f64
    when :isize then @isize
    when :ptr then @ptr
    when :struct_ptr then @ptr
    when :struct_ptr_opaque then @ptr
    when :struct_value then
      @gtypes[ctx.reach[ref.single!].llvm_name].fields_struct_type
    else raise NotImplementedError.new(ref.llvm_use_type(ctx))
    end
  end

  def llvm_mem_type_of(ref : Reach::Ref)
    case ref.llvm_mem_type(ctx)
    when :i1 then @i1
    when :i8 then @i8
    when :i16 then @i16
    when :i32 then @i32
    when :i64 then @i64
    when :f32 then @f32
    when :f64 then @f64
    when :isize then @isize
    when :ptr then @ptr
    when :struct_ptr then @ptr
    when :struct_ptr_opaque then @ptr
    when :struct_value then
      @gtypes[ctx.reach[ref.single!].llvm_name].fields_struct_type
    else raise NotImplementedError.new(ref.llvm_mem_type(ctx))
    end
  end

  def gtype_of(reach_ref : Reach::Ref)
    @gtypes[ctx.reach[reach_ref.single!].llvm_name]
  end

  def gtype_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    gtype_of(type_of(expr, in_gfunc))
  end

  def gtypes_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    type_of(expr, in_gfunc).each_defn.map do |defn|
      llvm_name = ctx.reach[defn].llvm_name
      @gtypes[llvm_name]
    end.to_a
  end

  def alloc_ctx
    # Return the stored value if we have it cached for this function already.
    return func_frame.alloc_ctx if func_frame.alloc_ctx?

    gen_at_entry do
      # Call the alloc_ctx function and save the value to refer to it later.
      func_frame.alloc_ctx = @runtime.gen_alloc_ctx_get(self)
    end
  end

  def run(ctx : Context)
    @ctx = ctx
    @di.ctx = ctx

    # Generate all type descriptors and function declarations.
    ctx.reach.each_type_def.each do |type_def|
      @gtypes[type_def.llvm_name] = GenType.new(self, type_def)
    end

    # Generate all struct types.
    @gtypes.each_value(&.gen_struct_type(self))

    # Generate all function declarations.
    @gtypes.each_value(&.gen_func_decls(self))

    # Generate all global descriptors.
    @gtypes.each_value(&.gen_desc(self))

    # Generate all global descriptor initializers.
    @gtypes.each_value(&.gen_desc_init(self))

    # Generate all global values associated with this type.
    @gtypes.each_value(&.gen_singleton(self))

    # Generate all Savi-supplied FFI-accessible functions.
    gen_savi_supplied_ffi_funcs

    # Generate all function implementations.
    @gtypes.each_value(&.gen_func_impls(self))

    # Generate the internal main function.
    @runtime.gen_main(self)

    # Generate the wrapper main function for the JIT.
    gen_wrapper

    # Do some last-minute tidying up.
    gen_tidy_up

    # Finish up debugging info.
    @di.finish

    # Run LLVM sanity checks on the generated module.
    begin
      @mod.verify
    rescue ex
      FileUtils.mkdir_p(File.dirname(Binary.path_for(ctx)))
      @mod.print_to_file("#{Binary.path_for(ctx)}.ll")
      Error.at Source::Pos.none, "LLVM #{ex.message}", [
        {Source::Pos.none,
          "please submit an issue ticket with this failure output and attach " +
          "the dumped LLVM IR file located at: #{Binary.path_for(ctx)}.ll"}
      ]
    end
  end

  def gen_savi_supplied_ffi_funcs
    @mod.functions.add("savi_cast_pointer", [@ptr], @ptr) { |f|
      gen_func_start(f)
      @builder.ret(f.params[0])
      gen_func_end
    }
  end

  def gen_wrapper # TODO: Bring back the JIT or remove this code.
    # Declare the wrapper function for the JIT.
    wrapper = @mod.functions.add("__savi_jit", ([] of LLVM::Type), @i32)
    wrapper.linkage = LLVM::Linkage::External

    # Create a basic block to hold the implementation of the main function.
    bb = wrapper.basic_blocks.append("entry")
    finish_block_and_move_to(bb)

    # Construct the following arguments to pass to the main function:
    # i32 argc = 0, i8** argv = ["savijit", NULL], i8** envp = [NULL]
    argc = @i32.const_int(1)
    argv = @builder.alloca(@ptr.array(2), "argv")
    envp = @builder.alloca(@ptr.array(1), "envp")
    argv_0 = @builder.inbounds_gep(@ptr.array(2), argv, @i32_0, @i32_0, "argv_0")
    argv_1 = @builder.inbounds_gep(@ptr.array(2), argv, @i32_0, @i32.const_int(1), "argv_1")
    envp_0 = @builder.inbounds_gep(@ptr.array(1), envp, @i32_0, @i32_0, "envp_0")
    @builder.store(gen_cstring("savijit"), argv_0)
    @builder.store(@ptr.null, argv_1)
    @builder.store(@ptr.null, envp_0)

    # Call the main function with the constructed arguments.
    res = gen_call_named("main", [argc, argv_0, envp_0], "res")
    @builder.ret(res)
  end

  # Do some basic housekeeping tasks to ensure LLVM doesn't yell at us.
  def gen_tidy_up
    # Any functions that have private linkage and no body need to have a
    # dummy body inserted - otherwise LLVM will complain that they look
    # like forward-declarations, which cannot have private linkage.
    @mod.functions.each { |f|
      next unless f.basic_blocks.last?.nil?           # skip defined functions
      next unless f.linkage == LLVM::Linkage::Private # skip external functions
      gen_func_start(f)
      @builder.unreachable
      gen_func_end
    }
  end

  def gen_func_start(llvm_func, gtype : GenType? = nil, gfunc : GenFunc? = nil)
    @frames << Frame.new(self, llvm_func, gtype, gfunc)

    # Add debug info for this function
    @di.func_start(gfunc, llvm_func) if gfunc

    # Start building from the entry block.
    finish_block_and_move_to(func_frame.entry_block)

    # Add a start block after the entry block, which will be our first normal
    # block, with the entry block being reserved for allocs and such.
    # The entry block transitions directly into the start block,
    # but we may come back and add to the entry block later.
    start_block = gen_block("start")
    @builder.br(start_block)
    @builder.position_at_end(start_block)

    # We have some extra work to do here if this is a yielding function.
    if gfunc && gfunc.needs_continuation?
      # We need to pre-declare the code blocks that follow each yield statement.
      # TODO: store these in the func_frame instead of the gfunc because
      # the gfunc is shared across multiple llvm_funcs.
      gfunc.after_yield_blocks = [] of LLVM::BasicBlock
      ctx.inventory[gfunc.link].yield_count.times do |index|
        gfunc.after_yield_blocks << gen_block("after_yield_#{index + 1}")
      end

      is_continue = gfunc.continue_llvm_func == llvm_func

      # Always start by grabbing the object holding the continuation data
      # and extract from it the receiver, locals, etc.
      gfunc.continuation_info.on_func_start(func_frame, is_continue)

      # For the continuation function, we will jump directly to the block
      # that follows the yield statement that last ran in the previous call,
      # according to the next_yield_index stored in the continuation data.
      if is_continue
        gfunc.continuation_info.jump_according_to_next_yield_index(
          func_frame,
          gfunc.after_yield_blocks,
        )
        unused_entry_block = gen_block("unused_entry")
        finish_block_and_move_to(unused_entry_block)
        return
      end
    end

    # Store each parameter in an alloca (or the continuation, if present)
    if gfunc && !gfunc.func.has_tag?(:ffi)
      gfunc.func.params.try(&.terms.each do |param|
        ref = func_frame.refer[param].as(Refer::Local)
        param_idx = ref.param_idx.not_nil!
        param_idx -= 1 unless gfunc.needs_receiver?
        param_idx += 1 if gfunc.needs_continuation?
        value = frame.llvm_func.params[param_idx]
        alloca = gen_local_alloca(ref, value.type)
        func_frame.current_locals[ref] = alloca
        @builder.store(value, alloca)
      end)
    end
  end

  def gen_func_end(gfunc = nil)
    @di.func_end if gfunc

    finish_block

    raise "invalid try else stack" unless @try_else_stack.empty?

    @frames.pop
  end

  def gen_within_foreign_frame(gtype : GenType, gfunc : GenFunc)
    frame = Frame.new(self, gfunc.llvm_func, gtype, gfunc)
    gen_within_foreign_frame(frame) { yield }
  end

  def gen_within_foreign_frame(frame : Frame)
    @frames << frame

    result = yield

    @frames.pop

    result
  end

  def gen_block(name)
    frame.llvm_func.basic_blocks.append(name)
  end

  def gen_call_named(
    func_name : String,
    args : Array(LLVM::Value),
    value_name : String = ""
  ) : LLVM::Value
    func = @mod.functions[func_name]
    @builder.call(func.function_type, func, args, value_name)
  end

  def gen_call_gfunc(
    gfunc : GenFunc,
    args : Array(LLVM::Value),
    value_name : String = ""
  ) : LLVM::Value
    func = gfunc.llvm_func
    @builder.call(func.function_type, func, args, value_name)
  end

  def gen_llvm_func(name, param_types, ret_type)
    @mod.functions.add(name, param_types, ret_type) { |f|
      # Give the function private linkage unless the flag to keep all functions
      # has been provided (in which case we use external linkage to preserve them)
      f.linkage = ctx.options.llvm_keep_fns \
        ? LLVM::Linkage::External \
        : LLVM::Linkage::Private
      f.unnamed_addr = true

      yield f
    }
  end

  def use_external_llvm_func(name, param_types, ret_type, is_variadic = false)
    # Return the existing function if it already exists with external linkage.
    existing = @mod.functions[name]?
    return existing if existing && existing.linkage == LLVM::Linkage::External

    # Otherwise, try to declare it here.
    @mod.functions.add(name, param_types, ret_type, is_variadic) { |f|
      f.linkage = LLVM::Linkage::External
    }
  end

  def gen_func_decl(gtype, gfunc)
    ret_type = gfunc.calling_convention.llvm_func_ret_type(self, gfunc)

    # Get the LLVM types to use for the parameter types.
    param_types = [] of LLVM::Type
    mparam_types = [] of LLVM::Type if gfunc.needs_send?
    gfunc.reach_func.signature.params.map do |param|
      param_types << llvm_type_of(param)
      mparam_types << llvm_mem_type_of(param) if mparam_types
    end

    # Add implicit continuation parameter and/or receiver parameter if needed.
    if gfunc.needs_continuation?
      param_types.unshift(gfunc.continuation_info.struct_type.pointer)
    end
    if gfunc.needs_receiver?
      receiver_type =
        if gfunc.boxed_fields_receiver?(ctx)
          @ptr
        else
          llvm_type_of(gtype)
        end
      param_types.unshift(receiver_type)
    end

    # Store the function declaration. We'll generate the body later.
    gfunc.llvm_func = gen_llvm_func(gfunc.llvm_name, param_types, ret_type) {}

    # If the function is meant to always be inlined, mark the LLVM func as such.
    if gfunc.func.has_tag?(:inline)
      gfunc.llvm_func.add_attribute(LLVM::Attribute::AlwaysInline)
    end

    # We declare no additional virtual, send, or continue variants
    # if this is a hygienic function.
    return if gfunc.link.is_hygienic?

    # Nor do we declare anything additional for an FFI function.
    return if gfunc.func.has_tag?(:ffi)

    # Choose the strategy for the function that goes in the virtual table.
    # The virtual table is used for calling functions indirectly, and always
    # has an object-style receiver as the first parameter, for consistency.
    # However, some functions expect no receiver or expect a raw machine value,
    # so we may need a wrapper function that handles this case.
    gfunc.virtual_llvm_func =
      if !gfunc.needs_receiver?
        # If we didn't use a receiver parameter in the function signature,
        # we need to create a wrapper method for the virtual table that
        # includes a receiver parameter, but throws it away without using it.
        vtable_name = "#{gfunc.llvm_name}.VIRTUAL"
        vparam_types = param_types.dup
        vparam_types.unshift(@ptr)

        gen_llvm_func vtable_name, vparam_types, ret_type do |fn|
          next if gtype.type_def.is_abstract?(ctx) && (!gfunc.func.body || gfunc.func.cap.value != "non")

          gen_func_start(fn)

          forward_args =
            (vparam_types.size - 1).times.map { |i| fn.params[i + 1] }.to_a

          result = gen_call_gfunc(gfunc, forward_args)
          if ret_type == @void
            @builder.ret
          else
            @builder.ret result
          end

          gen_func_end
        end
      elsif param_types.first == gtype.fields_struct_type?
        # If the receiver parameter type is a struct value rather than pointer,
        # then this is a value type, so we need its virtual function that uses
        # an object-style pointer to dereference the pointer to use as a value.
        vtable_name = "#{gfunc.llvm_name}.VIRTUAL"
        vparam_types = param_types.dup
        vparam_types.shift
        vparam_types.unshift(@ptr)

        gen_llvm_func vtable_name, vparam_types, ret_type do |fn|
          next if gtype.type_def.is_abstract?(ctx) && (!gfunc.func.body || gfunc.func.cap.value != "non")

          gen_func_start(fn)

          forward_args =
            (vparam_types.size - 1).times.map { |i| fn.params[i + 1] }.to_a
          forward_args.unshift(gen_unboxed_fields(fn.params[0], gtype))

          result = gen_call_gfunc(gfunc, forward_args)
          if ret_type == @void
            @builder.ret
          else
            @builder.ret result
          end

          gen_func_end
        end
      elsif param_types.first != @ptr
        # If the receiver parameter type isn't a pointer, we assume
        # the pointer is a boxed machine value, so we need a wrapper function
        # that will unwrap the raw machine value to use as the receiver.
        elem_types = gtype.fields_struct_type.struct_element_types
        raise "expected the receiver type to be a raw machine value" \
          unless elem_types.last == param_types.first

        vtable_name = "#{gfunc.llvm_name}.VIRTUAL"
        vparam_types = param_types.dup
        vparam_types.shift
        vparam_types.unshift(@ptr)

        gen_llvm_func vtable_name, vparam_types, ret_type do |fn|
          next if gtype.type_def.is_abstract?(ctx) && (!gfunc.func.body || gfunc.func.cap.value != "non")

          gen_func_start(fn)

          forward_args =
            (vparam_types.size - 1).times.map { |i| fn.params[i + 1] }.to_a
          forward_args.unshift(gen_unboxed_value(fn.params[0], gtype))

          result = gen_call_gfunc(gfunc, forward_args)
          if ret_type == @void
            @builder.ret
          else
            @builder.ret result
          end

          gen_func_end
        end
      elsif gfunc.needs_continuation?
        gfunc.llvm_func # TODO: unwrap virtual continuation code, here and also in cases above
      else
        # Otherwise the function needs no wrapper; it can be naked in the table.
        gfunc.llvm_func
      end

    # If this is an async function, we need to generate a wrapper that sends
    # it as a message to be handled asynchronously by the dispatch function.
    # This is also the function that should go in the virtual table.
    if gfunc.needs_send?
      send_name = "#{gfunc.llvm_name}.SEND"
      msg_name = "#{gfunc.llvm_name}.SEND.MSG"

      # The return type is None, which is a pointer.
      none_ptr = @ptr

      # We'll fill in the implementation of this later, in gen_send_impl.
      gfunc.virtual_llvm_func = gfunc.send_llvm_func =
        gen_llvm_func(send_name, param_types, none_ptr) {}

      # We also need to create a message type to use in the send operation.
      gfunc.send_msg_llvm_type =
        @llvm.struct([@i32, @i32, @ptr] + mparam_types.not_nil!, msg_name)
    end

    # If this is a yielding function, we need to generate the alternate
    # version of it used for continuing from after a yield block finishes.
    if gfunc.needs_continuation?
      # Declare the continue function to handle all continues.
      continue_param_types = [
        gfunc.continuation_info.struct_type.pointer,
        gfunc.continuation_info.yield_in_llvm_type,
      ]
      if gfunc.needs_receiver?
        continue_param_types.unshift(llvm_type_of(gtype))
      end

      gfunc.continue_llvm_func =
        gen_llvm_func("#{gfunc.llvm_name}.CONTINUE", continue_param_types, ret_type) {}

      # And declare the virtual continue function used to handle virtual continues.
      virtual_continue_param_types = [
        llvm_type_of(gtype),
        gfunc.continuation_info.struct_type.pointer,
        gfunc.continuation_info.yield_in_llvm_type,
      ]
      gfunc.virtual_continue_llvm_func =
        if virtual_continue_param_types == continue_param_types
          gfunc.continue_llvm_func
        else
          gen_llvm_func "#{gfunc.llvm_name}.VIRTUAL.CONTINUE", virtual_continue_param_types, ret_type do |fn|
            next if gtype.type_def.is_abstract?(ctx) && (!gfunc.func.body || gfunc.func.cap.value != "non")

            gen_func_start(fn)

            forward_args =
              (virtual_continue_param_types.size - 1).times.map { |i| fn.params[i + 1] }.to_a

            result = @builder.call(
              gfunc.continue_llvm_func.not_nil!.function_type,
              gfunc.continue_llvm_func.not_nil!,
              forward_args,
            )
            if ret_type == @void
              @builder.ret
            else
              @builder.ret result
            end

            gen_func_end
          end
        end
    end
  end

  def gen_func_impl(gtype, gfunc, llvm_func)
    return gen_intrinsic(gtype, gfunc, llvm_func) if gfunc.func.has_tag?(:compiler_intrinsic)
    return gen_ffi_impl(gtype, gfunc, llvm_func) if gfunc.func.has_tag?(:ffi)

    # Fields with no initializer body can be skipped.
    return if gfunc.func.has_tag?(:field) && gfunc.func.body.nil?

    gen_func_start(llvm_func, gtype, gfunc)

    # Set a receiver value (the value of the self in this function).
    # Skip this in the event that it was already set in gen_func_start.
    unless func_frame.receiver_value?
      func_frame.receiver_value =
        if gfunc.needs_receiver?
          llvm_func.params[0]
        elsif gtype.singleton?
          gtype.singleton
        end
    end

    # Declare a "local" for the self in the debug info to aid in debugging.
    self_gep = gen_alloca(func_frame.receiver_value.type, "@")
    @builder.store(func_frame.receiver_value, self_gep)
    @di.declare_self_local(
      (gfunc.func.cap || gfunc.func.ident).pos,
      gtype.type_def.as_ref,
      self_gep,
    )

    # If this is a constructor, first assign any field initializers.
    if gfunc.func.has_tag?(:constructor)
      gtype.fields.each do |name, _|
        init_func =
          gtype.each_gfunc.find do |gfunc|
            gfunc.func.ident.value == name &&
            gfunc.func.has_tag?(:field) &&
            !gfunc.func.body.nil?
          end
        next if init_func.nil?

        call_args = [func_frame.receiver_value]
        init_value = gen_call_gfunc(init_func, call_args)
        gen_field_store(name, init_value)
      end
    end

    # Now generate code for the expressions in the function body.
    body = gfunc.func.body
    last_expr = nil
    last_value =
      if !body || body.terms.empty?
        gen_none
      elsif gfunc.func.has_tag?(:constant)
        last_expr = body.terms.last
        gen_expr(body.terms.last)
      else
        last_expr = body.terms.last
        gen_expr(body)
      end

    gfunc.calling_convention.gen_return(self, gfunc, last_value, last_expr) \
      unless body && func_frame.flow.jumps_away?(body)

    gen_func_end(gfunc)
  end

  def gen_ffi_decl(gfunc)
    params = gfunc.func.params.try(&.terms.map { |param|
      llvm_type_of(param, gfunc)
    }) || [] of LLVM::Type
    ret = llvm_type_of(gfunc.func.ret.not_nil!, gfunc)
    is_variadic = gfunc.func.has_tag?(:variadic)

    ffi_link_name = gfunc.func.metadata[:ffi_link_name].as(String)

    ffi_link_lib = gfunc.func.metadata[:ffi_link_lib]?.as(String?)
    if ffi_link_lib
      ctx.link_libraries_by_foreign_function[ffi_link_name] = ffi_link_lib
    end

    use_external_llvm_func(ffi_link_name, params, ret, is_variadic)
  end

  def gen_ffi_impl(gtype, gfunc, llvm_func)
    llvm_ffi_func = gen_ffi_decl(gfunc)

    gen_func_start(llvm_func, gtype, gfunc)

    param_count = llvm_func.params.size
    args = param_count.times.map { |i| llvm_func.params[i] }.to_a

    value = gen_ffi_call(gfunc, args)

    gen_return_value(value, nil)

    gen_func_end(gfunc)
  end

  def gen_ffi_call(gfunc, args)
    llvm_ffi_func = gen_ffi_decl(gfunc)

    # Now call the FFI function, according to its convention.
    case gfunc.calling_convention
    when GenFunc::Simple
      value = @builder.call(
        llvm_ffi_func.function_type,
        llvm_ffi_func,
        args,
      )
      value = gen_none if llvm_ffi_func.return_type == @void
      value
    when GenFunc::Errorable
      then_block = gen_block("invoke_then")
      else_block = gen_block("invoke_else")
      value = @builder.invoke llvm_ffi_func, args, then_block, else_block
      value = gen_none if llvm_ffi_func.return_type == @void

      # In the else block, make a landing pad to catch the Pony-style error,
      # then raise the value "None" it as a Savi-style error.
      finish_block_and_move_to(else_block)
      @builder.landing_pad(
        @pony_error_landing_pad_type,
        @pony_error_personality_fn,
        [] of LLVM::Value,
      )
      gen_raise_error(gen_none, nil)

      # In the then block, return the result value.
      finish_block_and_move_to(then_block)
      value
    else
      raise NotImplementedError.new(gfunc.calling_convention)
    end

    # And possibly cast the return type, for the same reasons
    # that we possibly cast the argument types earlier above.
    ret_type = llvm_type_of(gfunc.func.ret.not_nil!, gfunc)

    value
  end

  def gen_intrinsic_cpointer(gtype, gfunc, llvm_func)
    gen_func_start(llvm_func, gtype, gfunc)
    params = llvm_func.params

    llvm_type = llvm_type_of(gtype)
    elem_llvm_type = llvm_mem_type_of(gtype.type_def.cpointer_type_arg(ctx))
    elem_size_value = abi_size_of(elem_llvm_type)

    @builder.ret \
      case gfunc.func.ident.value
      when "_null", "null"
        llvm_type.null
      when "_alloc"
        llvm_func.add_attribute(LLVM::Attribute::NoAlias, LLVM::AttributeIndex::ReturnIndex)
        llvm_func.add_attribute(LLVM::Attribute::DereferenceableOrNull, LLVM::AttributeIndex::ReturnIndex, elem_size_value)
        llvm_func.add_attribute(LLVM::Attribute::Alignment, LLVM::AttributeIndex::ReturnIndex, PonyRT::HEAP_MIN)
        @runtime.gen_intrinsic_cpointer_alloc(self, params, llvm_type, elem_size_value)
      when "_realloc"
        llvm_func.add_attribute(LLVM::Attribute::NoAlias, LLVM::AttributeIndex::ReturnIndex)
        llvm_func.add_attribute(LLVM::Attribute::DereferenceableOrNull, LLVM::AttributeIndex::ReturnIndex, elem_size_value)
        llvm_func.add_attribute(LLVM::Attribute::Alignment, LLVM::AttributeIndex::ReturnIndex, PonyRT::HEAP_MIN)
        @runtime.gen_intrinsic_cpointer_realloc(self, params, llvm_type, elem_size_value)
      when "_unsafe", "_unsafe_val"
        params[0]
      when "_offset", "offset"
        @builder.inbounds_gep(elem_llvm_type, params[0], params[1])
      when "_get_at"
        gep = @builder.inbounds_gep(elem_llvm_type, params[0], params[1])
        @builder.load(elem_llvm_type, gep)
      when "_get_at_no_alias"
        gep = @builder.inbounds_gep(elem_llvm_type, params[0], params[1])
        @builder.load(elem_llvm_type, gep)
      when "_assign_at"
        gep = @builder.inbounds_gep(elem_llvm_type, params[0], params[1])
        new_value = params[2]
        @builder.store(new_value, gep)
        new_value
      when "_displace_at"
        gep = @builder.inbounds_gep(elem_llvm_type, params[0], params[1])
        new_value = params[2]
        old_value = @builder.load(elem_llvm_type, gep)
        @builder.store(new_value, gep)
        old_value
      when "_copy_to"
        @builder.call(@memcpy.function_type, @memcpy, [
          params[1],
          params[0],
          @builder.mul(params[2], @isize.const_int(elem_size_value)),
          @i1.const_int(0),
        ])
        gen_none
      when "_compare"
        gen_call_named("memcmp", [params[0], params[1], params[2]])
      when "_hash"
        gen_call_named("ponyint_hash_block", [params[0], params[1]])
      when "is_null"
        @builder.is_null(params[0])
      when "is_not_null"
        @builder.is_not_null(params[0])
      when "address"
        @builder.ptr_to_int(params[0], @isize)
      else
        raise NotImplementedError.new(gfunc.func.ident.value)
      end

    gen_func_end
  end

  def gen_intrinsic_platform(gtype, gfunc, llvm_func)
    gen_func_start(llvm_func, gtype, gfunc)

    target = Target.new(@target_machine.triple)

    @builder.ret \
      case gfunc.func.ident.value
      when "is_linux"
        gen_bool(target.linux?)
      when "is_bsd"
        gen_bool(target.bsd?)
      when "is_macos"
        gen_bool(target.macos?)
      when "is_posix"
        gen_bool(!target.windows?)
      when "is_windows"
        gen_bool(target.windows?)
      when "is_ilp32"
        gen_bool(abi_size_of(@isize) == 4)
      when "is_lp64"
        gen_bool(abi_size_of(@isize) == 8)
      when "is_llp64"
        gen_bool(false) # TODO: this is 64-bit windows, instead of lp64
      when "is_big_endian"
        gen_bool(@target_machine.data_layout.big_endian?)
      when "is_little_endian"
        gen_bool(@target_machine.data_layout.little_endian?)
      else
        raise NotImplementedError.new(gfunc.func.ident.value)
      end

    gen_func_end
  end

  def gen_intrinsic_inhibit_optimization(gtype, gfunc, llvm_func)
    gen_func_start(llvm_func, gtype, gfunc)
    params = llvm_func.params

    @builder.ret \
      case gfunc.func.ident.value
      when "[]"
        param_type = params[0].type
        asm_fn_type = LLVM::Type.function([param_type], @void)
        asm_fn = LLVM::Function.from_value(
          asm_fn_type.inline_asm("", "imr,~{memory}", true, false)
        )
        call = @builder.call(asm_fn_type, asm_fn, [params[0]])
        call.add_instruction_attribute(
          LLVM::AttributeIndex::FunctionIndex.to_u32,
          LLVM::Attribute::NoUnwind, @llvm)
        call.add_instruction_attribute(
          LLVM::AttributeIndex::FunctionIndex.to_u32,
          LLVM::Attribute::InaccessibleMemOrArgMemOnly, @llvm)
        call.add_instruction_attribute(
          LLVM::AttributeIndex::FunctionIndex.to_u32,
          LLVM::Attribute::ReadOnly, @llvm) \
            if param_type.kind == LLVM::Type::Kind::Pointer
        gen_none
      when "observe_side_effects"
        asm_fn_type = LLVM::Type.function([] of LLVM::Type, @void)
        asm_fn = LLVM::Function.from_value(
          asm_fn_type.inline_asm("", "~{memory}", true, false)
        )
        call = @builder.call(asm_fn_type, asm_fn, [] of LLVM::Value)
        call.add_instruction_attribute(
          LLVM::AttributeIndex::FunctionIndex.to_u32,
          LLVM::Attribute::NoUnwind, @llvm)
        call.add_instruction_attribute(
          LLVM::AttributeIndex::FunctionIndex.to_u32,
          LLVM::Attribute::InaccessibleMemOrArgMemOnly, @llvm)
        gen_none
      else
        raise NotImplementedError.new(gfunc.func.ident.value)
      end

    gen_func_end
  end

  def gen_intrinsic(gtype, gfunc, llvm_func)
    return gen_intrinsic_cpointer(gtype, gfunc, llvm_func) if gtype.type_def.is_cpointer?(ctx)
    return gen_intrinsic_platform(gtype, gfunc, llvm_func) if gtype.type_def.is_platform?(ctx)
    return gen_intrinsic_inhibit_optimization(gtype, gfunc, llvm_func) if gtype.type_def.is_inhibit_optimization?(ctx)

    raise NotImplementedError.new(gtype.type_def) \
      unless gtype.type_def.is_numeric?(ctx)

    gen_func_start(llvm_func, gtype, gfunc)

    params = llvm_func.params

    already_returned = false # set to true if the intrinsic does a return in it
    return_value =
      case gfunc.func.ident.value
      when "as_val"
        params[0]
      when "bit_width"
        @i8.const_int(
          abi_size_of(llvm_type_of(gtype)) * 8
        )
      when "byte_width"
        @i8.const_int(
          abi_size_of(llvm_type_of(gtype))
        )
      when "zero"
        if gtype.type_def.is_floating_point_numeric?(ctx)
          case bit_width_of(gtype)
          when 32 then llvm_type_of(gtype).const_float(0)
          when 64 then llvm_type_of(gtype).const_double(0)
          else raise NotImplementedError.new(bit_width_of(gtype))
          end
        else
          llvm_type_of(gtype).const_int(0)
        end
      when "one"
        if gtype.type_def.is_floating_point_numeric?(ctx)
          case bit_width_of(gtype)
          when 32 then llvm_type_of(gtype).const_float(1)
          when 64 then llvm_type_of(gtype).const_double(1)
          else raise NotImplementedError.new(bit_width_of(gtype))
          end
        else
          llvm_type_of(gtype).const_int(1)
        end
      when "min_value"
        if gtype.type_def.is_floating_point_numeric?(ctx)
          raise NotImplementedError.new("float min_value compiler intrinsic")
        else
          if gtype.type_def.is_signed_numeric?(ctx)
            case bit_width_of(gtype)
            when 1 then llvm_type_of(gtype).const_int(1)
            when 8 then llvm_type_of(gtype).const_int(0x80)
            when 16 then llvm_type_of(gtype).const_int(0x8000)
            when 32 then llvm_type_of(gtype).const_int(0x80000000)
            when 64 then llvm_type_of(gtype).const_int(0x8000000000000000)
            else raise NotImplementedError.new(bit_width_of(gtype))
            end
          else
            llvm_type_of(gtype).const_int(0)
          end
        end
      when "max_value"
        if gtype.type_def.is_floating_point_numeric?(ctx)
          raise NotImplementedError.new("float max_value compiler intrinsic")
        else
          if gtype.type_def.is_signed_numeric?(ctx)
            case bit_width_of(gtype)
            when 1 then llvm_type_of(gtype).const_int(0)
            when 8 then llvm_type_of(gtype).const_int(0x7f)
            when 16 then llvm_type_of(gtype).const_int(0x7fff)
            when 32 then llvm_type_of(gtype).const_int(0x7fffffff)
            when 64 then llvm_type_of(gtype).const_int(0x7fffffffffffffff)
            else raise NotImplementedError.new(bit_width_of(gtype))
            end
          else
            case bit_width_of(gtype)
            when 1 then llvm_type_of(gtype).const_int(1)
            when 8 then llvm_type_of(gtype).const_int(0xff)
            when 16 then llvm_type_of(gtype).const_int(0xffff)
            when 32 then llvm_type_of(gtype).const_int(0xffffffff)
            when 64 then llvm_type_of(gtype).const_int(0xffffffffffffffff)
            else raise NotImplementedError.new(bit_width_of(gtype))
            end
          end
        end
      when "u8" then gen_numeric_conv(gtype, @gtypes["U8"], params[0])
      when "u8!" then gen_numeric_conv(gtype, @gtypes["U8"], params[0], partial: true)
      when "u16" then gen_numeric_conv(gtype, @gtypes["U16"], params[0])
      when "u16!" then gen_numeric_conv(gtype, @gtypes["U16"], params[0], partial: true)
      when "u32" then gen_numeric_conv(gtype, @gtypes["U32"], params[0])
      when "u32!" then gen_numeric_conv(gtype, @gtypes["U32"], params[0], partial: true)
      when "u64" then gen_numeric_conv(gtype, @gtypes["U64"], params[0])
      when "u64!" then gen_numeric_conv(gtype, @gtypes["U64"], params[0], partial: true)
      when "usize" then gen_numeric_conv(gtype, @gtypes["USize"], params[0])
      when "usize!" then gen_numeric_conv(gtype, @gtypes["USize"], params[0], partial: true)
      when "i8" then gen_numeric_conv(gtype, @gtypes["I8"], params[0])
      when "i8!" then gen_numeric_conv(gtype, @gtypes["I8"], params[0], partial: true)
      when "i16" then gen_numeric_conv(gtype, @gtypes["I16"], params[0])
      when "i16!" then gen_numeric_conv(gtype, @gtypes["I16"], params[0], partial: true)
      when "i32" then gen_numeric_conv(gtype, @gtypes["I32"], params[0])
      when "i32!" then gen_numeric_conv(gtype, @gtypes["I32"], params[0], partial: true)
      when "i64" then gen_numeric_conv(gtype, @gtypes["I64"], params[0])
      when "i64!" then gen_numeric_conv(gtype, @gtypes["I64"], params[0], partial: true)
      when "isize" then gen_numeric_conv(gtype, @gtypes["ISize"], params[0])
      when "isize!" then gen_numeric_conv(gtype, @gtypes["ISize"], params[0], partial: true)
      when "f32" then gen_numeric_conv(gtype, @gtypes["F32"], params[0])
      when "f32!" then gen_numeric_conv(gtype, @gtypes["F32"], params[0], partial: true)
      when "f64" then gen_numeric_conv(gtype, @gtypes["F64"], params[0])
      when "f64!" then gen_numeric_conv(gtype, @gtypes["F64"], params[0], partial: true)
      when "==" then
        if gtype.type_def.is_floating_point_numeric?(ctx)
          @builder.fcmp(LLVM::RealPredicate::OEQ, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::EQ, params[0], params[1])
        end
      when "!=" then
        if gtype.type_def.is_floating_point_numeric?(ctx)
          @builder.fcmp(LLVM::RealPredicate::ONE, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::NE, params[0], params[1])
        end
      when "<" then
        if gtype.type_def.is_floating_point_numeric?(ctx)
          @builder.fcmp(LLVM::RealPredicate::OLT, params[0], params[1])
        elsif gtype.type_def.is_signed_numeric?(ctx)
          @builder.icmp(LLVM::IntPredicate::SLT, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::ULT, params[0], params[1])
        end
      when "<=" then
        if gtype.type_def.is_floating_point_numeric?(ctx)
          @builder.fcmp(LLVM::RealPredicate::OLE, params[0], params[1])
        elsif gtype.type_def.is_signed_numeric?(ctx)
          @builder.icmp(LLVM::IntPredicate::SLE, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::ULE, params[0], params[1])
        end
      when ">" then
        if gtype.type_def.is_floating_point_numeric?(ctx)
          @builder.fcmp(LLVM::RealPredicate::OGT, params[0], params[1])
        elsif gtype.type_def.is_signed_numeric?(ctx)
          @builder.icmp(LLVM::IntPredicate::SGT, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::UGT, params[0], params[1])
        end
      when ">=" then
        if gtype.type_def.is_floating_point_numeric?(ctx)
          @builder.fcmp(LLVM::RealPredicate::OGE, params[0], params[1])
        elsif gtype.type_def.is_signed_numeric?(ctx)
          @builder.icmp(LLVM::IntPredicate::SGE, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::UGE, params[0], params[1])
        end
      when "+" then
        if gtype.type_def.is_floating_point_numeric?(ctx)
          @builder.fadd(params[0], params[1])
        else
          @builder.add(params[0], params[1])
        end
      when "-" then
        if gtype.type_def.is_floating_point_numeric?(ctx)
          @builder.fsub(params[0], params[1])
        else
          @builder.sub(params[0], params[1])
        end
      when "*" then
        if gtype.type_def.is_floating_point_numeric?(ctx)
          @builder.fmul(params[0], params[1])
        else
          @builder.mul(params[0], params[1])
        end
      when "/", "%" then
        if gtype.type_def.is_floating_point_numeric?(ctx)
          if gfunc.func.ident.value == "/"
            @builder.fdiv(params[0], params[1])
          else
            @builder.frem(params[0], params[1])
          end
        else # we need to some extra work to avoid an undefined result value
          params[0].name = "numerator"
          params[1].name = "denominator"

          llvm_type = llvm_type_of(gtype)
          zero = llvm_type.const_int(0)
          nonzero_block = gen_block(".div.nonzero")
          nonoverflow_block = gen_block(".div.nonoverflow") \
            if gtype.type_def.is_signed_numeric?(ctx)
          after_block = gen_block(".div.after")

          blocks = [] of LLVM::BasicBlock
          values = [] of LLVM::Value

          # Return zero if dividing by zero.
          nonzero = @builder.icmp LLVM::IntPredicate::NE, params[1], zero,
            "#{params[1].name}.nonzero"
          @builder.cond(nonzero, nonzero_block, after_block)
          blocks << @builder.insert_block.not_nil!
          values << zero
          finish_block_and_move_to(nonzero_block)

          # If signed, return zero if this operation would overflow.
          # This happens for exactly one case in each signed integer type.
          # In `I8`, the overflow case is `-128 / -1`, which would be 128.
          if gtype.type_def.is_signed_numeric?(ctx)
            bad = @builder.not(zero)
            denom_good = @builder.icmp LLVM::IntPredicate::NE, params[1], bad,
              "#{params[1].name}.nonoverflow"

            bits = llvm_type.const_int(bit_width_of(gtype) - 1)
            bad = @builder.shl(bad, bits)
            numer_good = @builder.icmp LLVM::IntPredicate::NE, params[0], bad,
              "#{params[0].name}.nonoverflow"

            either_good = @builder.or(numer_good, denom_good, "nonoverflow")

            @builder.cond(either_good, nonoverflow_block.not_nil!, after_block)
            blocks << @builder.insert_block.not_nil!
            values << zero
            finish_block_and_move_to(nonoverflow_block.not_nil!)
          end

          # Otherwise, compute the result.
          result =
            case {gtype.type_def.is_signed_numeric?(ctx), gfunc.func.ident.value}
            when {true, "/"} then @builder.sdiv(params[0], params[1])
            when {true, "%"} then @builder.srem(params[0], params[1])
            when {false, "/"} then @builder.udiv(params[0], params[1])
            when {false, "%"} then @builder.urem(params[0], params[1])
            else raise NotImplementedError.new(gtype.type_def.llvm_name)
            end
          result.name = "result"
          @builder.br(after_block)
          blocks << @builder.insert_block.not_nil!
          values << result
          finish_block_and_move_to(after_block)

          # Get the final result, which may be zero from one of the pre-checks.
          @builder.phi(llvm_type, blocks, values, "phidiv")
        end
      when "bit_and"
        raise "bit_and float" if gtype.type_def.is_floating_point_numeric?(ctx)
        @builder.and(params[0], params[1])
      when "bit_or"
        raise "bit_or float" if gtype.type_def.is_floating_point_numeric?(ctx)
        @builder.or(params[0], params[1])
      when "bit_xor"
        raise "bit_xor float" if gtype.type_def.is_floating_point_numeric?(ctx)
        @builder.xor(params[0], params[1])
      when "bit_shl"
        raise "bit_shl float" if gtype.type_def.is_floating_point_numeric?(ctx)

        bits = params[1]
        all_bits = @i8.const_int(bit_width_of(gtype))
        is_all = @builder.icmp(LLVM::IntPredicate::UGE, bits, all_bits)

        zero_block = gen_block("zero")
        normal_block = gen_block("normal")
        @builder.cond(is_all, zero_block, normal_block)

        finish_block_and_move_to(zero_block)
        @builder.ret(llvm_type_of(gtype).const_int(0))

        finish_block_and_move_to(normal_block)
        @builder.shl(params[0], gen_numeric_conv(@gtypes["U8"], gtype, bits))
      when "bit_shr"
        raise "bit_shr float" if gtype.type_def.is_floating_point_numeric?(ctx)

        bits = params[1]
        all_bits = @i8.const_int(bit_width_of(gtype))
        is_all = @builder.icmp(LLVM::IntPredicate::UGE, bits, all_bits)

        zero_block = gen_block("zero")
        normal_block = gen_block("normal")
        @builder.cond(is_all, zero_block, normal_block)

        finish_block_and_move_to(zero_block)
        @builder.ret(llvm_type_of(gtype).const_int(0))

        finish_block_and_move_to(normal_block)
        @builder.lshr(params[0], gen_numeric_conv(@gtypes["U8"], gtype, bits))
      when "invert"
        raise "invert float" if gtype.type_def.is_floating_point_numeric?(ctx)
        @builder.not(params[0])
      when "reverse_bits"
        raise "reverse_bits float" if gtype.type_def.is_floating_point_numeric?(ctx)
        op_func =
          case bit_width_of(gtype)
          when 1
            use_external_llvm_func("llvm.bitreverse.i1", [@i1], @i1)
          when 8
            use_external_llvm_func("llvm.bitreverse.i8", [@i8], @i8)
          when 16
            use_external_llvm_func("llvm.bitreverse.i16", [@i16], @i16)
          when 32
            use_external_llvm_func("llvm.bitreverse.i32", [@i32], @i32)
          when 64
            use_external_llvm_func("llvm.bitreverse.i64", [@i64], @i64)
          else raise NotImplementedError.new(bit_width_of(gtype))
          end
        @builder.call(op_func.function_type, op_func, [params[0]])
      when "swap_bytes"
        raise "swap_bytes float" if gtype.type_def.is_floating_point_numeric?(ctx)
        case bit_width_of(gtype)
        when 1, 8
          params[0]
        when 16
          op_func =
            use_external_llvm_func("llvm.bswap.i16", [@i16], @i16)
          @builder.call(op_func.function_type, op_func, [params[0]])
        when 32
          op_func =
            use_external_llvm_func("llvm.bswap.i32", [@i32], @i32)
          @builder.call(op_func.function_type, op_func, [params[0]])
        when 64
          op_func =
            use_external_llvm_func("llvm.bswap.i64", [@i64], @i64)
          @builder.call(op_func.function_type, op_func, [params[0]])
        else raise NotImplementedError.new(bit_width_of(gtype))
        end
      when "leading_zero_bits"
        raise "leading_zero_bits float" if gtype.type_def.is_floating_point_numeric?(ctx)
        op_func =
          case bit_width_of(gtype)
          when 1
            use_external_llvm_func("llvm.ctlz.i1", [@i1, @i1], @i1)
          when 8
            use_external_llvm_func("llvm.ctlz.i8", [@i8, @i1], @i8)
          when 32
            use_external_llvm_func("llvm.ctlz.i32", [@i32, @i1], @i32)
          when 16
            use_external_llvm_func("llvm.ctlz.i16", [@i16, @i1], @i16)
          when 64
            use_external_llvm_func("llvm.ctlz.i64", [@i64, @i1], @i64)
          else raise NotImplementedError.new(bit_width_of(gtype))
          end
        gen_numeric_conv gtype, @gtypes["U8"],
          @builder.call(op_func.function_type, op_func, [params[0], @i1_false])
      when "trailing_zero_bits"
        raise "trailing_zero_bits float" if gtype.type_def.is_floating_point_numeric?(ctx)
        op_func =
          case bit_width_of(gtype)
          when 1
            use_external_llvm_func("llvm.cttz.i1", [@i1, @i1], @i1)
          when 8
            use_external_llvm_func("llvm.cttz.i8", [@i8, @i1], @i8)
          when 16
            use_external_llvm_func("llvm.cttz.i16", [@i16, @i1], @i16)
          when 32
            use_external_llvm_func("llvm.cttz.i32", [@i32, @i1], @i32)
          when 64
            use_external_llvm_func("llvm.cttz.i64", [@i64, @i1], @i64)
          else raise NotImplementedError.new(bit_width_of(gtype))
          end
        gen_numeric_conv gtype, @gtypes["U8"],
          @builder.call(op_func.function_type, op_func, [params[0], @i1_false])
      when "total_one_bits"
        raise "total_one_bits float" if gtype.type_def.is_floating_point_numeric?(ctx)
        op_func =
          case bit_width_of(gtype)
          when 1
            use_external_llvm_func("llvm.ctpop.i1", [@i1], @i1)
          when 8
            use_external_llvm_func("llvm.ctpop.i8", [@i8], @i8)
          when 16
            use_external_llvm_func("llvm.ctpop.i16", [@i16], @i16)
          when 32
            use_external_llvm_func("llvm.ctpop.i32", [@i32], @i32)
          when 64
            use_external_llvm_func("llvm.ctpop.i64", [@i64], @i64)
          else raise NotImplementedError.new(bit_width_of(gtype))
          end
        gen_numeric_conv gtype, @gtypes["U8"], \
          @builder.call(op_func.function_type, op_func, [params[0]])
      when "+!", "-!", "*!"
        raise NotImplementedError.new("overflow-checked arithmetic for float") \
          if gtype.type_def.is_floating_point_numeric?(ctx)
        basename =
          case gfunc.func.ident.value
          when "+!" then gtype.type_def.is_signed_numeric?(ctx) ? "sadd" : "uadd"
          when "-!" then gtype.type_def.is_signed_numeric?(ctx) ? "ssub" : "usub"
          when "*!" then gtype.type_def.is_signed_numeric?(ctx) ? "smul" : "umul"
          else raise NotImplementedError.new(gfunc.func.ident.value)
          end
        op_func =
          case bit_width_of(gtype)
          when 1
            use_external_llvm_func("llvm.#{basename}.with.overflow.i1",
              [@i1, @i1], @llvm.struct([@i1, @i1]))
          when 8
            use_external_llvm_func("llvm.#{basename}.with.overflow.i8",
              [@i8, @i8], @llvm.struct([@i8, @i1]))
          when 16
            use_external_llvm_func("llvm.#{basename}.with.overflow.i16",
              [@i16, @i16], @llvm.struct([@i16, @i1]))
          when 32
            use_external_llvm_func("llvm.#{basename}.with.overflow.i32",
              [@i32, @i32], @llvm.struct([@i32, @i1]))
          when 64
            use_external_llvm_func("llvm.#{basename}.with.overflow.i64",
              [@i64, @i64], @llvm.struct([@i64, @i1]))
          else raise NotImplementedError.new(bit_width_of(gtype))
          end

        overflow_block = gen_block("overflow")
        after_block = gen_block("after")

        result = @builder.call(op_func.function_type, op_func, [params[0], params[1]])

        is_overflow = @builder.extract_value(result, 1)
        @builder.cond(is_overflow, overflow_block, after_block)

        finish_block_and_move_to(overflow_block)
        gfunc.calling_convention.gen_error_return(self, gfunc, gen_none, nil)

        finish_block_and_move_to(after_block)
        result_value = @builder.extract_value(result, 0)
        gfunc.calling_convention.gen_return(self, gfunc, result_value, nil)

        .tap { already_returned = true }
      when "saturating_add", "saturating_subtract"
        raise NotImplementedError.new("saturating_add for float") \
          if gtype.type_def.is_floating_point_numeric?(ctx)
        basename =
          case gfunc.func.ident.value
          when "saturating_add"
            gtype.type_def.is_signed_numeric?(ctx) ? "sadd" : "uadd"
          when "saturating_subtract"
            gtype.type_def.is_signed_numeric?(ctx) ? "ssub" : "usub"
          else
            raise NotImplementedError.new(gfunc.func.ident.value)
          end
        op_func =
          case bit_width_of(gtype)
          when 1
            use_external_llvm_func("llvm.#{basename}.sat.i1", [@i1, @i1], @i1)
          when 8
            use_external_llvm_func("llvm.#{basename}.sat.i8", [@i8, @i8], @i8)
          when 16
            use_external_llvm_func("llvm.#{basename}.sat.i16", [@i16, @i16], @i16)
          when 32
            use_external_llvm_func("llvm.#{basename}.sat.i32", [@i32, @i32], @i32)
          when 64
            use_external_llvm_func("llvm.#{basename}.sat.i64", [@i64, @i64], @i64)
          else raise NotImplementedError.new(bit_width_of(gtype))
          end

        @builder.call(op_func.function_type, op_func, [params[0], params[1]])
      when "bits"
        raise "bits integer" unless gtype.type_def.is_floating_point_numeric?(ctx)
        case bit_width_of(gtype)
        when 32 then @builder.bit_cast(params[0], @i32)
        when 64 then @builder.bit_cast(params[0], @i64)
        else raise NotImplementedError.new(bit_width_of(gtype))
        end
      when "from_bits"
        raise "from_bits integer" unless gtype.type_def.is_floating_point_numeric?(ctx)
        case bit_width_of(gtype)
        when 32 then @builder.bit_cast(params[0], @f32)
        when 64 then @builder.bit_cast(params[0], @f64)
        else raise NotImplementedError.new(bit_width_of(gtype))
        end
      when "log"
        raise "log integer" unless gtype.type_def.is_floating_point_numeric?(ctx)
        op_func =
          case bit_width_of(gtype)
          when 32
            use_external_llvm_func("llvm.log.f32", [@f32], @f32)
          when 64
            use_external_llvm_func("llvm.log.f64", [@f64], @f64)
          else raise NotImplementedError.new(bit_width_of(gtype))
          end
        @builder.call(op_func.function_type, op_func, [params[0]])
      when "log2"
        raise "log2 integer" unless gtype.type_def.is_floating_point_numeric?(ctx)
        op_func =
          case bit_width_of(gtype)
          when 32
            use_external_llvm_func("llvm.log2.f32", [@f32], @f32)
          when 64
            use_external_llvm_func("llvm.log2.f64", [@f64], @f64)
          else raise NotImplementedError.new(bit_width_of(gtype))
          end
        @builder.call(op_func.function_type, op_func, [params[0]])
      when "log10"
        raise "log10 integer" unless gtype.type_def.is_floating_point_numeric?(ctx)
        op_func =
          case bit_width_of(gtype)
          when 32
            use_external_llvm_func("llvm.log10.f32", [@f32], @f32)
          when 64
            use_external_llvm_func("llvm.log10.f64", [@f64], @f64)
          else raise NotImplementedError.new(bit_width_of(gtype))
          end
        @builder.call(op_func.function_type, op_func, [params[0]])
      when "pow"
        raise "pow integer" unless gtype.type_def.is_floating_point_numeric?(ctx)
        op_func =
          case bit_width_of(gtype)
          when 32
            use_external_llvm_func("llvm.pow.f32", [@f32, @f32], @f32)
          when 64
            use_external_llvm_func("llvm.pow.f64", [@f64, @f64], @f64)
          else raise NotImplementedError.new(bit_width_of(gtype))
          end
        @builder.call(op_func.function_type, op_func, [params[0], params[1]])
      when "next_pow2"
        raise "next_pow2 float" if gtype.type_def.is_floating_point_numeric?(ctx)

        arg =
          if bit_width_of(gtype) > bit_width_of(@isize)
            @builder.trunc(params[0], @isize)
          else
            @builder.zext(params[0], @isize)
          end
        res = gen_call_named("ponyint_next_pow2", [arg])

        if bit_width_of(gtype) < bit_width_of(@isize)
          @builder.trunc(res, llvm_type_of(gtype))
        else
          @builder.zext(res, llvm_type_of(gtype))
        end
      when "wide_multiply"
        raise "wide_multiply float" if gtype.type_def.is_floating_point_numeric?(ctx)

        narrow_type, wide_type =
          case bit_width_of(gtype)
          when 1 then {@i1, @i8}
          when 8 then {@i8, @i16}
          when 16 then {@i16, @i32}
          when 32 then {@i32, @i64}
          when 64 then {@i64, @i128}
          else raise NotImplementedError.new(bit_width_of(gtype))
          end

        # Get the product of multiplying the two operands in the wide type,
        # catching all significant bits without overflow.
        wide = @builder.mul(
          @builder.zext(params[0], wide_type),
          @builder.zext(params[1], wide_type),
        )

        # Obtain the most significant half via shift right of the narrow width.
        wide_msb = @builder.lshr(wide,
          wide_type.const_int(bit_width_of(narrow_type))
        )

        # Convert the two halves back to the narrow type.
        narrow_msb = @builder.trunc(wide_msb, narrow_type)
        narrow_lsb = @builder.trunc(wide, narrow_type)

        # Return the two halves as a pair.
        narrow_pair = gfunc.llvm_func.return_type.undef
        narrow_pair = @builder.insert_value(narrow_pair, narrow_msb, 0)
        narrow_pair = @builder.insert_value(narrow_pair, narrow_lsb, 1)
        narrow_pair
      else
        raise NotImplementedError.new(gfunc.func.ident.inspect)
      end

    gen_return_value(return_value, nil) unless already_returned

    gen_func_end
  end

  def resolve_call(call : AST::Call, in_gfunc : GenFunc? = nil)
    member_ast = call.ident
    lhs_type = type_of(call.receiver, in_gfunc)
    member = member_ast.value

    if lhs_type.is_abstract?(ctx)
      # Even if there are multiple possible gtypes and thus gfuncs, we choose an
      # arbitrary one for the purposes of checking arg types against param types.
      # However we must take care to choose the right signature if there are
      # multiple signatures available, so we find the right reach_func.
      # TODO: This logic could be tidied up quite a bit with better abstractions.
      reach_func : Reach::Func? = nil
      in_gfunc ||= func_frame.gfunc.not_nil!
      pre_infer = ctx.pre_infer[in_gfunc.reach_func.reified.link]
      in_gfunc.infer.each_called_func_within(ctx, in_gfunc.reach_func.reified, pre_infer[call]) { |info, called_rf|
        reach_func = ctx.reach.reach_func_for(called_rf)
      }
      reach_func = reach_func.not_nil!

      lhs_gtype = @gtypes[lhs_type.any_callable_def_for(ctx, member).llvm_name]
      call_gfunc = lhs_gtype.gfuncs_by_sig_name[reach_func.signature.codegen_compat_name(ctx)]
    else
      lhs_gtype = @gtypes[lhs_type.any_callable_def_for(ctx, member).llvm_name]
      call_gfunc = lhs_gtype[member]
    end

    {lhs_gtype, call_gfunc}
  end

  def resolve_yielding_call_cont_type(call : AST::Call, in_gfunc : GenFunc? = nil) : LLVM::Type
    member_ast = call.ident
    lhs_type = type_of(call.receiver, in_gfunc)
    member = member_ast.value

    lhs_call_defs = lhs_type.all_callable_concrete_defs_for(ctx, member)
    concrete_gfuncs = lhs_call_defs.map { |reach_def| @gtypes[reach_def.llvm_name][member] }

    if concrete_gfuncs.size <= 1
      concrete_gfuncs.first.not_nil!.continuation_info.struct_type
    else
      ContinuationInfo.virtual_struct_type(self, concrete_gfuncs)
    end
  end

  def gen_dot(call : AST::Call) # TODO: rename as gen_call ?
    member_ast = call.ident
    args_ast = call.args
    yield_params_ast = call.yield_params
    yield_block_ast = call.yield_block

    member = member_ast.value
    arg_exprs = args_ast.try(&.terms.map(&.as(AST::Node?))) || [] of AST::Node?
    args = arg_exprs.map { |x| gen_expr(x.not_nil!) }
    arg_frames = arg_exprs.map { nil.as(Frame?) }

    lhs_type = type_of(call.receiver)
    lhs_gtype, gfunc = resolve_call(call)

    # Generate code for the receiver, whether we actually use it or not.
    # We trust LLVM optimizations to eliminate dead code when it does nothing.
    receiver = gen_expr(call.receiver)

    # For any args we are missing, try to find and use a default param value.
    gfunc.func.params.try do |params|
      while args.size < params.terms.size
        param = params.terms[args.size]

        param_default = AST::Extract.param(param)[2]

        raise "missing arg #{args.size + 1} with no default param:"\
          "\n#{call.pos.show}" unless param_default

        # Somewhat hacky unwrapping to aid the source_code_position_of_argument check below.
        param_default = param_default.terms.first \
          if param_default.is_a?(AST::Group) && param_default.terms.size == 1

        arg_exprs << param_default
        arg_frames << gen_within_foreign_frame(lhs_gtype, gfunc) { func_frame }

        if param_default.is_a?(AST::Prefix) \
        && param_default.op.value == "source_code_position_of_argument"
          # If this is supposed to be a literal representing the source code of
          # an argument, we first must find the index of the argument specified.
          foreign_refer = gen_within_foreign_frame(lhs_gtype, gfunc) { func_frame.refer }
          find_ref = foreign_refer[param_default.term]
          found_index = \
            params.terms.index { |o| foreign_refer[AST::Extract.param(o)[0]] == find_ref }

          # Now, generate a value representing the source code pos of that arg.
          if found_index
            args << gen_source_code_pos(arg_exprs[found_index].not_nil!.pos)
          else
            # If there is no index of the arg, we must be referencing the yield.
            args << gen_source_code_pos(call.yield_block.not_nil!.terms.last.pos)
          end
        else
          gen_within_foreign_frame lhs_gtype, gfunc do
            func_frame.receiver_value = receiver
            args << gen_expr(param_default)
          end
        end
      end
    end

    # Determine if we need to use a virtual call and if we need the receiver.
    needs_virtual_call = lhs_type.is_abstract?(ctx)
    use_receiver = gfunc.needs_receiver? || needs_virtual_call || gfunc.needs_send?
    llvm_func =
      if needs_virtual_call
        gen_vtable_func_get(
          receiver,
          lhs_type,
          gfunc.vtable_index,
          member,
        )
      elsif gfunc.needs_send?
        gfunc.send_llvm_func
      else
        gfunc.llvm_func
      end

    # If this is a constructor, the receiver must be allocated first.
    if gfunc.func.has_tag?(:constructor)
      raise "can't do a virtual call on a constructor" if needs_virtual_call
      receiver =
        if lhs_gtype.type_def.has_allocation?(ctx)
          gen_alloc(lhs_gtype, call, "#{lhs_gtype.type_def.llvm_name}.new")
        else
          gen_alloc_alloca(lhs_gtype, "#{lhs_gtype.type_def.llvm_name}.new")
        end
    end

    # Prepend the continuation to the args list if necessary.
    cont = nil
    if gfunc.needs_continuation?
      cont = gen_yielding_call_cont_gep(call, "#{gfunc.llvm_name}.CONT")

      args.unshift(cont.not_nil!)
      arg_exprs.unshift(nil)
      arg_frames.unshift(nil)
    end

    # Prepend the receiver to the args list if necessary,
    # or store it in the continuation if we are using one.
    use_receiver = false
    if gfunc.needs_receiver? || needs_virtual_call || gfunc.needs_send?
      # The receiver must be stored in a gep if this is a yielding call,
      # since it isn't guaranteed to be in every continue path.
      if gfunc.needs_continuation?
        receiver_gep = gen_yielding_call_receiver_gep(call, "#{gfunc.llvm_name}.@")
        @builder.store(receiver, receiver_gep)
      end

      args.unshift(receiver)
      arg_exprs.unshift(call.receiver)
      arg_frames.unshift(nil)
      use_receiver = true
    end

    # Call the LLVM function, or do a virtual call if necessary.
    @di.set_loc(call.ident)
    result = gen_call(
      gfunc.reach_func.signature,
      gfunc,
      llvm_func,
      args,
      arg_exprs,
      arg_frames,
      gfunc.func.has_tag?(:ffi) ? gfunc : nil,
      needs_virtual_call,
      use_receiver,
      !cont.nil?,
    )

    # If this was an FFI call, skip calling-convention-specific handling.
    return result if gfunc.func.has_tag?(:ffi)

    case gfunc.calling_convention
    when GenFunc::Simple
      # Do nothing - we already have the result value we need.
    when GenFunc::Constructor
      # The result is the receiver we sent over as an argument.
      result = receiver if gfunc.func.has_tag?(:constructor) # TODO: can this condition be removed? it should always be true, right?
      result = gen_unboxed_fields(result, lhs_gtype) if gfunc.boxed_fields_receiver?(ctx)
    when GenFunc::Errorable
      # If this is an error-able function, check the error bit in the tuple.
      error_bit = @builder.extract_value(result, 1)

      error_block = gen_block("error_return")
      after_block = gen_block("after_return")

      is_error = @builder.icmp(LLVM::IntPredicate::EQ, error_bit, @i1_true)
      @builder.cond(is_error, error_block, after_block)

      finish_block_and_move_to(error_block)
      # TODO: Should we try to avoid destructuring and restructuring the
      # tuple value here? Or does LLVM optimize it away so as to not matter?
      gen_raise_error(@builder.extract_value(result, 0), call)

      finish_block_and_move_to(after_block)
      result = @builder.extract_value(result, 0)
    when GenFunc::Yielding, GenFunc::YieldingErrorable
      # We declare the alloca itself, as well as bit casted aliases.
      # Declare some code blocks in which we'll generate this pseudo-loop.
      maybe_block = gen_block("maybe_yield_block")
      yield_block = gen_block("yield_block")
      continue_block = gen_block("continue_block")
      if gfunc.can_error?
        check_error_block = gen_block("check_error_block")
        error_block = gen_block("error_block")
      end
      after_final_return_block = gen_block("after_final_return")
      after_block = gen_block("after_call")

      # We start at the "maybe block" right after the first call above.
      # We'll also return here after subsequent continue calls below.
      # The "maybe block" makes the determination of whether or not to jump to
      # the yield block, based on the function pointer in the continuation.
      # If the function pointer is NULL, then that means there is no more
      # continuing to be done, and therefore the yield block shouldn't be run.
      # If the function pointer is non-NULL, we go to the yield block.
      @builder.br(maybe_block)
      finish_block_and_move_to(maybe_block)
      is_finished = gfunc.continuation_info.check_is_finished(cont.not_nil!)
      @builder.cond(is_finished, check_error_block || after_final_return_block, yield_block)

      # If applicable, generate the code for checking error of the result,
      # as well as the code for raising the error if it was present.
      if check_error_block
        finish_block_and_move_to(check_error_block)
        is_error = gfunc.continuation_info.check_is_error(cont.not_nil!)
        @builder.cond(is_error, error_block.not_nil!, after_final_return_block)

        finish_block_and_move_to(error_block.not_nil!)
        # TODO: Allow an error value of something other than None.
        gen_raise_error(gen_none, call)
      end

      # Move our cursor to the yield block to start generating code there.
      finish_block_and_move_to(yield_block)

      # If the yield block uses yield params, we treat them as locals,
      # which means they need a gep to be able to load them later.
      # We get the values from the continuation data.
      if yield_params_ast
        yield_out_all = gfunc.continuation_info.get_yield_out(cont.not_nil!)

        yield_params_ast.terms.each_with_index do |yield_param_ast, index|
          @di.set_loc(yield_param_ast)

          yield_param_ref = func_frame.refer[yield_param_ast]
          yield_param_ref = yield_param_ref.as(Refer::Local)
          yield_param_alloca =
            gen_local_alloca(yield_param_ref, llvm_type_of(yield_param_ast))

          yield_out = @builder.extract_value(yield_out_all, index, yield_param_ref.name)
          @builder.store(yield_out, yield_param_alloca)
        end
      end

      # Prepare an entry on the jump-catching stacks in case a break or next is
      # encountered while generating code for the yield block body.
      final_phi_type = type_of_unless_unsatisfiable(call) || @gtypes["None"].type_def.as_ref
      yield_in_type = gfunc.continuation_info.yield_in_type
      @loop_break_stack << {
        after_block,
        [] of LLVM::BasicBlock,
        [] of LLVM::Value,
        final_phi_type,
      }
      @loop_next_stack << {
        continue_block,
        [] of LLVM::BasicBlock,
        [] of LLVM::Value,
        yield_in_type,
      }

      # Now we generate the actual code for the yield block.
      # If None is the yield in value type expected, just generate None,
      # allowing us to ignore the actual result value of the yield block.
      yield_in_value = gen_expr(yield_block_ast.not_nil!)
      yield_in_value = gen_none if yield_in_type.is_none?
      yield_in_block = @builder.insert_block.not_nil!
      @builder.br(continue_block)

      # In the continue block we may need to use a phi node to catch values
      # that were passed via next instead of the normal block result value.
      finish_block_and_move_to(continue_block)
      next_stack_tuple = @loop_next_stack.pop
      raise "invalid next stack" unless next_stack_tuple[0] == continue_block
      if next_stack_tuple[1].any?
        phi_blocks = [yield_in_block] + next_stack_tuple[1]
        phi_values = [yield_in_value] + next_stack_tuple[2]
        yield_in_value = @builder.phi(llvm_type_of(yield_in_type), phi_blocks, phi_values, "phi_call_next")
      end

      # We're now ready to call the continue function for this function.
      # We pass the continuation data and yield_in_value back as the arguments.
      continue_llvm_func_type : LLVM::Type =
        if needs_virtual_call
          gfunc.virtual_continue_llvm_func.function_type
        else
          gfunc.continue_llvm_func.not_nil!.function_type
        end
      continue_llvm_func =
        if needs_virtual_call
          gen_vtable_func_get(
            receiver,
            lhs_type,
            gfunc.vtable_index_continue,
            "#{member}.CONTINUE",
          )
        else
          gfunc.continue_llvm_func.not_nil!
        end
      again_args = [cont.not_nil!, yield_in_value]
      again_arg_frames = arg_exprs.map { nil.as(Frame?) }
      if use_receiver
        again_receiver = @builder.load(
          llvm_type_of(call.receiver),
          receiver_gep.not_nil!,
          "#{gfunc.llvm_name}.@",
        )
        again_args.unshift(again_receiver)
        again_arg_frames.unshift(nil)
      end
      @di.set_loc(call.ident)
      @builder.call(
        continue_llvm_func_type,
        LLVM::Function.from_value(continue_llvm_func),
        again_args,
      )

      # Return to the "maybe block", to determine if we need to iterate again.
      @builder.br(maybe_block)

      # Finally, finish with the "real" result of the call.
      finish_block_and_move_to(after_final_return_block)
      final_return_result = gfunc.continuation_info.get_final_return(cont.not_nil!)
      @builder.br(after_block)

      # Now generate code for the phi that follows the result, which is what
      # joins up the value from multiple branches if we have any breaks present.
      finish_block_and_move_to(after_block)
      break_stack_tuple = @loop_break_stack.pop
      raise "invalid break stack" unless break_stack_tuple[0] == after_block
      result = if func_frame.classify.value_needed?(call)
        if break_stack_tuple[1].empty?
          final_return_result
        else
          phi_blocks = [after_final_return_block] + break_stack_tuple[1]
          phi_values = [final_return_result] + break_stack_tuple[2]
          @builder.phi(llvm_type_of(final_phi_type), phi_blocks, phi_values, "phi_call")
        end
      else
        gen_none
      end
    else
      raise NotImplementedError.new(gfunc.calling_convention)
    end

    result
  end

  def gen_vtable_func_get(
    receiver : LLVM::Value,
    type_ref : Reach::Ref,
    vtable_index : Int32,
    name : String,
  )
    receiver.name = type_ref.show_type if receiver.name.empty?
    rname = receiver.name
    fname = "#{rname}.#{name}"

    # Load the type descriptor of the receiver so we can read its vtable,
    # then load the function pointer from the appropriate index of that vtable.
    desc = gen_get_desc(receiver)
    vtable_gep = @runtime.gen_vtable_gep_get(self, desc, "#{rname}.DESC.VTABLE")
    vtable_idx = @i32.const_int(vtable_index)
    gep = @builder.inbounds_gep(
      @ptr,
      @builder.inbounds_gep(@ptr, vtable_gep, @i32_0, "#{fname}.VTABLE.ARRAY"),
      vtable_idx,
      "#{fname}.GEP"
    )
    func = @builder.load(@ptr, gep, "#{fname}.LOAD")

    func
  end

  def gen_call(
    signature : Reach::Signature,
    signature_gfunc : GenFunc,
    func : (LLVM::Function | LLVM::Value),
    args : Array(LLVM::Value),
    arg_exprs : Array(AST::Node?),
    arg_frames : Array(Frame?),
    is_ffi_gfunc : GenFunc?,
    is_virtual_call : Bool,
    use_receiver : Bool,
    use_cont : Bool,
  )
    llvm_func_type =
      if func.is_a?(LLVM::Function)
        func.function_type
      elsif is_virtual_call
        signature_gfunc.virtual_llvm_func.function_type
      else
        signature_gfunc.llvm_func.function_type
      end

    # Get the list of parameter types, prepending the receiver type
    # and/or the continuation type if either or both is in use.
    param_types = signature.params.map(&.as(Reach::Ref?))
    param_types.unshift(nil) if use_cont
    param_types.unshift(signature.receiver) if use_receiver

    # Cast the arguments to the parameter types.
    cast_args = [] of LLVM::Value
    param_types.to_a.each_with_index do |param_type, index|
      arg = args[index]

      # Don't cast if we don't know what to cast to.
      if !param_type
        cast_args << arg
        next
      end

      # Don't cast if the LLVM type already matches.
      llvm_param_type = llvm_func_type.params_types[index]
      if arg.type == llvm_param_type
        cast_args << arg
        next
      end

      arg_expr = arg_exprs[index].not_nil!
      arg_frame = arg_frames[index]
      cast_args << gen_assign_cast(arg, param_type, llvm_param_type, arg_expr, arg_frame)
    end

    # Handle the special case of calling an FFI function. We need to call it
    # directly instead of using the indirection of the normal gfunc.llvm_func
    # that wraps it, since there is not a reliable way to transmit varargs via
    # that wrapper function (the only way is to use thunk and musttail attrs,
    # but the musttail attr is unnecessarily restrictive for what we need).
    if is_ffi_gfunc
      # For variadic FFI functions, we may have more args than params,
      # but the cast args we have collected are mapped to the known params.
      # So here we add the remaining (not cast) args to the cast args array.
      while args.size > cast_args.size
        cast_args << args[cast_args.size]
      end
      return gen_ffi_call(is_ffi_gfunc, cast_args)
    end

    @builder.call(llvm_func_type, func, cast_args)
  end

  def gen_eq(relate)
    ref = func_frame.refer[relate.lhs]
    value = gen_expr(relate.rhs)
    name = value.name
    lhs_type =
      if ref.is_a?(Refer::Local)
        type_of(func_frame.any_defn_for_local(ref))
      else
        type_of(relate.lhs)
      end
    lhs_llvm_type = llvm_type_of(lhs_type)

    cast_value = gen_assign_cast(value, lhs_type, nil, relate.rhs)
    cast_value.name = value.name

    @runtime.gen_expr_post(self, relate.lhs, cast_value)

    @di.set_loc(relate.op)
    if ref.is_a?(Refer::Local)
      @builder.store(cast_value, gen_local_alloca(ref, lhs_llvm_type))
    else
      raise NotImplementedError.new(relate.inspect)
    end

    cast_value
  end

  def gen_displacing_eq(relate)
    ref = func_frame.refer[relate.lhs]
    value = gen_expr(relate.rhs)
    name = value.name
    lhs_type =
      if ref.is_a?(Refer::Local)
        type_of(func_frame.any_defn_for_local(ref))
      else
        type_of(relate.lhs)
      end
    lhs_llvm_type = llvm_type_of(lhs_type)

    cast_value = gen_assign_cast(value, lhs_type, nil, relate.rhs)
    cast_value.name = value.name

    @runtime.gen_expr_post(self, relate.lhs, cast_value)

    local_ref = ref.as(Refer::Local)
    alloca = func_frame.current_locals[local_ref]

    @di.set_loc(relate.op)

    displaced_value = gen_assign_cast(
      @builder.load(lhs_llvm_type, alloca, local_ref.as(Refer::Local).name),
      type_of(relate),
      nil,
      func_frame.any_defn_for_local(local_ref),
    )

    @builder.store(cast_value, alloca)

    displaced_value
  end

  def gen_field_eq(node : AST::FieldWrite)
    value = gen_expr(node.rhs)
    name = value.name

    value = gen_assign_cast(value, type_of(node), nil, node.rhs)
    value.name = name

    @di.set_loc(node)
    gen_field_store(node.value, value)
    value
  end

  def gen_field_displace(node : AST::FieldDisplace)
    old_value = gen_field_load(node.value)

    value = gen_expr(node.rhs)
    name = value.name

    value = gen_assign_cast(value, type_of(node), nil, node.rhs)
    value.name = name

    @di.set_loc(node)
    gen_field_store(node.value, value)

    old_value
  end

  def gen_check_identity_equal(relate : AST::Relate, positive_check : Bool)
    gen_check_identity_equal_inner(
      gen_expr(relate.lhs),
      gen_expr(relate.rhs),
      type_of(relate.lhs),
      type_of(relate.rhs),
      relate.pos,
      positive_check,
    )
  end

  def gen_check_identity_equal_inner(
    lhs : LLVM::Value,
    rhs : LLVM::Value,
    lhs_type : Reach::Ref,
    rhs_type : Reach::Ref,
    pos : Source::Pos,
    positive_check : Bool
  )
    pred = positive_check ? LLVM::IntPredicate::EQ : LLVM::IntPredicate::NE

    # If the values are floating point values, they should be compared by their
    # bits, so that we can avoid complexities with things like NaN comparison.
    # We define floating point identity to be defined in terms of its bits.
    if lhs.type.kind == LLVM::Type::Kind::Double
      lhs = @builder.bit_cast(lhs, @i64)
    elsif lhs.type.kind == LLVM::Type::Kind::Float
      lhs = @builder.bit_cast(lhs, @i32)
    end
    if rhs.type.kind == LLVM::Type::Kind::Double
      rhs = @builder.bit_cast(rhs, @i64)
    elsif rhs.type.kind == LLVM::Type::Kind::Float
      rhs = @builder.bit_cast(rhs, @i32)
    end

    if lhs.type.kind == LLVM::Type::Kind::Integer \
    && rhs.type.kind == LLVM::Type::Kind::Integer
      if lhs.type == rhs.type
        # Integers of the same type are compared by integer comparison.
        @builder.icmp(
          pred,
          lhs,
          rhs,
          "#{lhs.name}.is.#{rhs.name}",
        )
      else
        # Integers of different types never have the same identity.
        gen_bool(!positive_check)
      end
    elsif lhs.type.kind == LLVM::Type::Kind::Struct \
      && rhs.type.kind == LLVM::Type::Kind::Struct
      if lhs.type == rhs.type
        # Structs of the same type are compared by field-wise comparison.
        # TODO: This will eventually be generated by earlier stages of the
        # compiler which will also be responsible for equality checks with `==`,
        # which will have the same default semantics for structs as `===`,
        # unless the user overrides a custom definition for `==`
        # (but even in that case, we should have a standard definition of `===`)
        phi_blocks = [] of LLVM::BasicBlock
        phi_values = [] of LLVM::Value
        post_block = gen_block("structs.identity.compare")
        success_block = gen_block("structs.identity.compare.success")

        last_compare = gen_bool(true) # with no fields, the comparison succeeds.
        gtype = gtype_of(lhs_type)
        gtype.fields.each_with_index { |(field_name, field_type), index|
          next_block = gen_block("structs.identity.compare.#{field_name}")

          phi_values << gen_bool(!positive_check)
          phi_blocks << @builder.insert_block.not_nil!
          @builder.cond(
            last_compare,
            positive_check ? next_block : post_block,
            positive_check ? post_block : next_block
          )

          @builder.position_at_end(next_block)
          last_compare = gen_check_identity_equal_inner(
            @builder.extract_value(lhs, index, "#{lhs.name}.#{field_name}"),
            @builder.extract_value(lhs, index, "#{rhs.name}.#{field_name}"),
            field_type,
            field_type,
            pos,
            positive_check,
          )
        }
        phi_values << gen_bool(!positive_check)
        phi_blocks << @builder.insert_block.not_nil!
        @builder.cond(last_compare, success_block, post_block)

        @builder.position_at_end(success_block)
        phi_values << gen_bool(positive_check)
        phi_blocks << @builder.insert_block.not_nil!
        @builder.br(post_block)

        @builder.position_at_end(post_block)
        @builder.phi(@i1, phi_blocks, phi_values)
      else
        # Structs of different types never have the same identity.
        gen_bool(!positive_check)
      end
    elsif (
      lhs_type == rhs_type || lhs.type == rhs.type || \
      lhs.type == @obj_ptr || rhs.type == @obj_ptr
    ) \
    && lhs.type.kind == LLVM::Type::Kind::Pointer \
    && rhs.type.kind == LLVM::Type::Kind::Pointer
      # Objects (not boxed machine words) of the same type are compared by
      # integer comparison of the pointer to the object.
      @builder.icmp(pred, lhs, rhs, "#{lhs.name}.is.#{rhs.name}")
    else
      raise NotImplementedError.new("this comparison:\n#{pos.show}")
    end
  end

  def gen_address_of(term_expr)
    ref = func_frame.refer[term_expr].as Refer::Local

    alloca = func_frame.current_locals[ref]

    alloca
  end

  def gen_identity_digest_of(term_expr)
    gen_identity_digest_of(gen_expr(term_expr), type_of(term_expr), term_expr.pos)
  end

  def gen_identity_digest_of(value, reach_type, pos)
    name = "identity_digest_of.#{value.name}"

    case value.type.kind
    when LLVM::Type::Kind::Float
      @builder.zext(@builder.bit_cast(value, @i32), @isize, name)
    when LLVM::Type::Kind::Double
      gen_identity_digest_of_i64(@builder.bit_cast(value, @i64), name)
    when LLVM::Type::Kind::Integer
      case value.type.int_width
      when @bitwidth
        value
      when 64
        gen_identity_digest_of_i64(value, name)
      else
        @builder.zext(value, @isize, name)
      end
    when LLVM::Type::Kind::Pointer
      if llvm_type_of(reach_type).kind == LLVM::Type::Kind::Pointer
        @builder.ptr_to_int(value, @isize, name)
      else
        # When the value is a pointer, but the type is not, the value is boxed.
        # Therefore, we must unwrap the boxed value and get its digest.
        # TODO: Implement this.
        raise NotImplementedError.new("unboxing digest:\n#{pos.show}")
      end
    when LLVM::Type::Kind::Struct
      gtype = gtype_of(reach_type)
      if value.type == gtype.fields_struct_type
        # For a struct, the identity digest of the composite is the total xor
        # over the identity digest of each field that is within the struct.
        result = @isize.const_int(0)
        gtype.fields.each_with_index { |(field_name, field_type), index|
          field_value = @builder.extract_value(value, index, "@.#{field_name}")
          result = @builder.xor(result,
            gen_identity_digest_of(field_value, field_type, pos)
          )
        }
        result
      else
        raise NotImplementedError.new("this digest:\n#{pos.show}")
      end
    else
      raise NotImplementedError.new("this digest:\n#{pos.show}")
    end
  end

  def gen_identity_digest_of_i64(value : LLVM::Value, name : String)
    raise "not i64" unless value.type == @i64

    case @bitwidth
    when 64
      value.name = name
      value
    when 32
      # On 32-bit platforms, the digest of an i64 only has 32 bits,
      # so we need to XOR the high and low halves together into one i32.
      @builder.xor(
        @builder.trunc(@builder.lshr(value, @i64.const_int(32)), @i32),
        @builder.trunc(value, @i32),
        name
      )
    else
      raise NotImplementedError.new(@bitwidth)
    end
  end

  def gen_check_subtype(relate : AST::Relate, positive_check : Bool)
    pre_infer = ctx.pre_infer[func_frame.gfunc.not_nil!.link]

    if pre_infer[relate.lhs].is_a?(Infer::FixedTypeExpr)
      # If the left-hand side is a fixed compile-time type (and knowing that
      # the right-hand side always is), we can return a compile-time true/false.
      gfunc = func_frame.gfunc.not_nil!
      lhs_meta_type = gfunc.reified.meta_type_of(ctx, relate.lhs, gfunc.infer).not_nil!
      rhs_meta_type = gfunc.reified.meta_type_of(ctx, relate.rhs, gfunc.infer).not_nil!

      result = lhs_meta_type.satisfies_bound?(ctx, rhs_meta_type)
      result = !result if !positive_check
      gen_bool(result)
    elsif type_of(relate.lhs).is_concrete?(ctx)
      # If the left side is an expression, but is statically known to have
      # a particular concrete type, we can resolve this check without looking
      # at the type descriptor. And indeed, it may have no type descriptor
      # if it is a bare value such as a struct or machine word type.
      #
      # This is the same code as the above, except we must first generate
      # code to execute the expression, in case it has any side effects.
      # But we discard the result value and just check the inferred types.
      gen_expr(relate.lhs)

      gfunc = func_frame.gfunc.not_nil!
      lhs_meta_type = gfunc.reified.meta_type_of(ctx, relate.lhs, gfunc.infer).not_nil!
      rhs_meta_type = gfunc.reified.meta_type_of(ctx, relate.rhs, gfunc.infer).not_nil!

      result = lhs_meta_type.satisfies_bound?(ctx, rhs_meta_type)
      result = !result if !positive_check
      gen_bool(result)
    else
      # Otherwise, we generate code that checks the type descriptor of the
      # left-hand side against the compile-time type of the right-hand side.
      gen_check_subtype_at_runtime(
        gen_expr(relate.lhs),
        type_of(relate.rhs),
        positive_check,
      )
    end
  end

  def gen_check_subtype_at_runtime(
    lhs : LLVM::Value,
    rhs_type : Reach::Ref,
    positive_check : Bool,
  )
    op_name = positive_check ? "<:" : "!<:"
    if rhs_type.is_concrete?(ctx)
      rhs_gtype = @gtypes[ctx.reach[rhs_type.single!].llvm_name]

      lhs_desc = gen_get_desc(lhs)
      rhs_desc = rhs_gtype.desc

      # For a positive check, we check if the type descriptors are equal.
      # For a negative check, we succeed if they are NOT equal.
      pred = positive_check ? LLVM::IntPredicate::EQ : LLVM::IntPredicate::NE
      @builder.icmp(pred, lhs_desc, rhs_desc, "#{lhs.name}#{op_name}")
    else
      type_def = rhs_type.single_def!(ctx)
      rhs_name = type_def.llvm_name
      trait_id = @isize.const_int(type_def.desc_id)

      # Based on the trait id, determine the values to use for bitmap testing.
      shift = @llvm.const_lshr(
        trait_id,
        @isize.const_int(Math.log2(@bitwidth).to_i),
      )
      mask = @llvm.const_shl(
        @isize.const_int(1),
        @llvm.const_and(trait_id, @isize.const_int(@bitwidth - 1)),
      )

      # Load the trait bitmap of the concrete type descriptor of the lhs.
      desc = gen_get_desc(lhs)
      traits = @runtime.gen_traits_get(self, desc, "#{lhs.name}.DESC.TRAITS")
      bits_gep = @builder.inbounds_gep(@isize.array(0), traits, @i32_0, shift, "#{lhs.name}.DESC.TRAITS.GEP.#{rhs_name}")
      bits = @builder.load(@isize, bits_gep, "#{lhs.name}.DESC.TRAITS.#{rhs_name}")

      # For a positive check, we check if the trait bit intersection is nonzero.
      # For a negative check, we succeed if it DOES equal zero.
      pred = positive_check ? LLVM::IntPredicate::NE : LLVM::IntPredicate::EQ
      @builder.icmp(
        pred,
        @builder.and(bits, mask, "#{lhs.name}<:#{rhs_name}.BITS"),
        @isize.const_int(0),
        "#{lhs.name}#{op_name}#{rhs_name}"
      )
    end
  end

  def gen_assign_cast(
    value : LLVM::Value,
    to_type : Reach::Ref,
    to_llvm_type : LLVM::Type?,
    from_expr : AST::Node,
    from_frame : Frame? = nil,
  )
    # TODO: Can we replace from_expr and from_frame with simply from_type?
    # That would simplify the callers, if the runtime never needs the AST.
    from_type =
      if from_frame
        gen_within_foreign_frame(from_frame) { type_of(from_expr) }
      else
        type_of(from_expr)
      end
    from_llvm_type = llvm_type_of(from_type)
    to_llvm_type ||= llvm_type_of(to_type)

    # Sometimes we may need to implicitly cast struct pointer to struct value.
    # We do that here by dereferencing the pointer.
    if value.type != from_llvm_type \
    && value.type.kind == LLVM::Type::Kind::Pointer
      value = gen_unboxed_fields(value, gtype_of(from_type))
    end
    from_llvm_type = value.type

    # We assert that the origin llvm type derived from type analysis is the
    # same as the actual type of the llvm value we are being asked to cast.
    raise "value type #{value.type} doesn't match #{from_llvm_type}:\n" +
      from_expr.pos.show \
        unless value.type == from_llvm_type

    # If the runtime-specific cast kind doesn't match,
    # we need to take a runtime-specific action prior to bit casting.
    from_kind = @runtime.cast_kind_of(self, from_type, from_llvm_type, from_expr.pos)
    to_kind   = @runtime.cast_kind_of(self, to_type, to_llvm_type, from_expr.pos)
    if from_kind != to_kind
      value = @runtime.gen_cast_value(self,
        value, from_kind, to_kind, from_type, to_type, from_expr)
    end

    value
  end

  def gen_boxed_value(value, gtype, from_expr)
    # Allocate a struct pointer to hold the type descriptor and value.
    # This also writes the type descriptor into it appropriate position.
    boxed = gen_alloc(gtype, from_expr, "#{value.name}.BOXED")

    # Write the value itself into the value field of the boxed struct pointer.
    @builder.store(
      value,
      @builder.struct_gep(
        gtype.fields_struct_type,
        @builder.struct_gep(
          gtype.struct_type,
          boxed,
          gtype.fields_struct_index,
          "#{value.name}.BOXED.FIELDS.GEP"
        ),
        0,
        "#{value.name}.BOXED.VALUE.GEP"
      )
    )

    # Return the boxed struct pointer.
    boxed
  end

  def gen_unboxed_value(boxed, gtype)
    # Load the value itself from the value field of the boxed struct pointer.
    @builder.load(
      gtype.fields_struct_type.struct_element_types[0],
      @builder.struct_gep(
        gtype.fields_struct_type,
        @builder.struct_gep(
          gtype.struct_type,
          boxed,
          gtype.fields_struct_index,
          "#{boxed.name}.FIELDS.GEP"
        ),
        0,
        "#{boxed.name}.VALUE.GEP"
      ),
      "#{boxed.name}.VALUE"
    )
  end

  def gen_boxed_fields(fields_value, gtype, from_expr)
    # Allocate a struct pointer to hold the type descriptor and value.
    # This also writes the type descriptor into it appropriate position.
    boxed = gen_alloc(gtype, from_expr, "#{fields_value.name}.BOXED")

    # Write the fields value into the fields struct of the boxed struct pointer.
    @builder.store(
      fields_value,
      @builder.struct_gep(
        gtype.struct_type,
        boxed,
        gtype.fields_struct_index,
        "#{fields_value.name}.BOXED.FIELDS.GEP"
      )
    )

    # Return the boxed struct pointer.
    boxed
  end

  def gen_unboxed_fields(boxed, gtype)
    # Load the fields value from the fields struct of the boxed struct pointer.
    @builder.load(
      gtype.fields_struct_type,
      @builder.struct_gep(
        gtype.struct_type,
        boxed,
        gtype.fields_struct_index,
        "#{boxed.name}.FIELDS.GEP"
      ),
      "#{boxed.name}.FIELDS"
    )
  end

  def gen_expr(expr : AST::Node, const_only = false) : LLVM::Value
    @di.set_loc(expr)

    value = \
    case expr
    when AST::Identifier
      ref = func_frame.refer[expr]
      if ref.is_a?(Refer::Local)
        local_ref = ref
        raise "#{local_ref.inspect} isn't a constant value" if const_only

        alloca = func_frame.current_locals[local_ref]
        gen_assign_cast(
          @builder.load(alloca.allocated_type, alloca, local_ref.name),
          type_of(expr),
          nil,
          func_frame.any_defn_for_local(ref),
        )
      elsif ref.is_a?(Refer::Type)
        enum_value = ref.with_value.try(&.resolve(ctx).value)
        if enum_value
          llvm_type_of(expr).const_int(enum_value)
        elsif ref.defn(ctx).has_tag?(:numeric)
          llvm_type = llvm_type_of(expr)
          case llvm_type.kind
          when LLVM::Type::Kind::Integer then llvm_type.const_int(0)
          when LLVM::Type::Kind::Float then llvm_type.const_float(0)
          when LLVM::Type::Kind::Double then llvm_type.const_double(0)
          else raise NotImplementedError.new(llvm_type)
          end
        else
          gtype_of(expr).singleton
        end
      elsif ref.is_a?(Refer::TypeParam)
        defn = gtype_of(expr).type_def.program_type.resolve(ctx)
        if defn.has_tag?(:numeric)
          llvm_type = llvm_type_of(expr)
          case llvm_type.kind
          when LLVM::Type::Kind::Integer then llvm_type.const_int(0)
          when LLVM::Type::Kind::Float then llvm_type.const_float(0)
          when LLVM::Type::Kind::Double then llvm_type.const_double(0)
          else raise NotImplementedError.new(llvm_type)
          end
        else
          gtype_of(expr).singleton
        end
      elsif ref.is_a?(Refer::TypeAlias)
        gtype_of(expr).singleton
      elsif ref.is_a?(Refer::Self)
        raise "#{ref.inspect} isn't a constant value" if const_only
        func_frame.receiver_value
      else
        raise NotImplementedError.new("#{ref}\n#{expr.pos.show}")
      end
    when AST::Jump
      case expr.kind
      when AST::Jump::Kind::Error
        # TODO: Allow an error value of something other than None.
        gen_raise_error(gen_expr(expr.term), expr.term)
      when AST::Jump::Kind::Return
        gen_return_value(gen_expr(expr.term), expr.term)
      when AST::Jump::Kind::Break
        gen_break_loop(gen_expr(expr.term), expr.term)
      when AST::Jump::Kind::Next
        gen_next(gen_expr(expr.term), expr.term)
      else
        raise NotImplementedError.new("for this kind of jump")
      end
    when AST::FieldRead
      gen_field_load(expr.value)
    when AST::FieldWrite
      gen_field_eq(expr)
    when AST::FieldDisplace
      gen_field_displace(expr)
    when AST::LiteralString
      case expr.prefix_ident.try(&.value)
      when nil then gen_string(expr.value)
      when "b" then gen_bstring(expr.value)
      else raise NotImplementedError.new(expr.prefix_ident)
      end
    when AST::LiteralCharacter
      gen_integer(expr)
    when AST::LiteralInteger
      gen_integer(expr)
    when AST::LiteralFloat
      gen_float(expr)
    when AST::Relate
      raise "#{expr.inspect} isn't a constant value" if const_only
      case expr.op.as(AST::Operator).value
      when "=" then gen_eq(expr)
      when "<<=" then gen_displacing_eq(expr)
      when "===" then gen_check_identity_equal(expr, true)
      when "!==" then gen_check_identity_equal(expr, false)
      when "<:" then gen_check_subtype(expr, true)
      when "!<:" then gen_check_subtype(expr, false)
      when "static_address_of_function" then gen_static_address_of_function(expr)
      else raise NotImplementedError.new(expr.inspect)
      end
    when AST::Group
      raise "#{expr.inspect} isn't a constant value" if const_only
      case expr.style
      when "(", ":" then gen_sequence(expr)
      when "["      then gen_dynamic_array(expr)
      else raise NotImplementedError.new(expr.inspect)
      end
    when AST::Call
      gen_dot(expr)
    when AST::Choice
      raise "#{expr.inspect} isn't a constant value" if const_only
      gen_choice(expr)
    when AST::Loop
      raise "#{expr.inspect} isn't a constant value" if const_only
      gen_loop(expr)
    when AST::Try
      raise "#{expr.inspect} isn't a constant value" if const_only
      gen_try(expr)
    when AST::Yield
      raise "#{expr.inspect} isn't a constant value" if const_only
      gen_yield(expr)
    when AST::Prefix
      case expr.op.value
      when "stack_address_of_variable"
        gen_stack_address_of_variable(expr, expr.term)
      when "reflection_of_type"
        gen_reflection_of_type(expr, expr.term)
      when "reflection_of_runtime_type_name"
        gen_reflection_of_runtime_type_name(expr, expr.term)
      when "identity_digest_of"
        gen_identity_digest_of(expr.term)
      when "--", "recover_UNSAFE"
        gen_expr(expr.term, const_only)
      else
        raise NotImplementedError.new(expr.inspect)
      end
    when AST::Qualify
      gtype_of(expr).singleton
    else
      raise NotImplementedError.new(expr.inspect)
    end

    value = @runtime.gen_expr_post(self, expr, value)

    # As a way of asserting that value_not_needed analysis has no false
    # "not needed" tags on expressions, if this expression is tagged as such,
    # we return a fake value instead of the evaluation of the expression,
    # expecting that later LLVM actions will fail loudly if this value is used.
    return gen_value_not_needed unless func_frame.classify.value_needed?(expr)

    value
  rescue exc : Exception
    raise Error.compiler_hole_at(expr, exc)
  end

  def gen_value_not_needed
    @value_not_needed.undef
  end

  def gen_none
    @gtypes["None"].singleton
  end

  def gen_bool(bool)
    @i1.const_int(bool ? 1 : 0)
  end

  def gen_integer(expr : (AST::LiteralInteger | AST::LiteralCharacter))
    type_ref = type_of(expr)
    case type_ref.llvm_use_type(ctx)
    when :i1 then @i1.const_int(expr.value.to_i8!)
    when :i8 then @i8.const_int(expr.value.to_i8!)
    when :i16 then @i16.const_int(expr.value.to_i16!)
    when :i32 then @i32.const_int(expr.value.to_i32!)
    when :i64 then @i64.const_int(expr.value.to_i64!)
    when :f32 then @f32.const_float(expr.value.to_f32!)
    when :f64 then @f64.const_double(expr.value.to_f64!)
    when :isize then @isize.const_int(
      (abi_size_of(@isize) == 8) \
      ? expr.value.to_i64!
      : expr.value.to_i32!
    )
    else raise "invalid numeric literal type: #{type_ref.inspect}"
    end
  end

  def gen_float(expr : AST::LiteralFloat)
    type_ref = type_of(expr)
    case type_ref.llvm_use_type(ctx)
    when :f32 then @f32.const_float(expr.value.to_f32)
    when :f64 then @f64.const_double(expr.value.to_f64)
    else raise "invalid floating point literal type: #{type_ref.inspect}"
    end
  end

  def gen_as_cond(value : LLVM::Value)
    case value.type
    when @i1 then value
    when @obj_ptr
      # When an object pointer, assume that it is a boxed Bool object,
      # meaning that we need to unbox it as such here. This will fail
      # in a silent and ugly way if the type system doesn't properly
      # ensure that the value we hold here is truly a Bool.
      gen_unboxed_value(value, @gtypes["Bool"])
    else
      raise NotImplementedError.new(value.type)
    end
  end

  def bit_width_of(gtype : GenType)
    bit_width_of(llvm_type_of(gtype))
  end

  def bit_width_of(llvm_type : LLVM::Type)
    return 1 if llvm_type == @i1
    abi_size_of(llvm_type) * 8
  end

  def gen_numeric_conv(
    from_gtype : GenType,
    to_gtype : GenType,
    value : LLVM::Value,
    partial : Bool = false,
  )
    from_signed = from_gtype.type_def.is_signed_numeric?(ctx)
    to_signed = to_gtype.type_def.is_signed_numeric?(ctx)
    from_float = from_gtype.type_def.is_floating_point_numeric?(ctx)
    to_float = to_gtype.type_def.is_floating_point_numeric?(ctx)
    from_width = bit_width_of(from_gtype)
    to_width = bit_width_of(to_gtype)

    to_llvm_type = llvm_type_of(to_gtype)

    if from_float && to_float
      if from_width < to_width
        @builder.fpext(value, to_llvm_type)
      elsif from_width > to_width
        raise "unexpected from_width: #{from_width}" unless from_width == 64
        raise "unexpected to_width: #{to_width}" unless to_width == 32
        gen_numeric_conv_f64_to_f32(value, partial)
      else
        value
      end
    elsif from_float && to_signed
      case from_width
      when 32 then gen_numeric_conv_f32_to_sint(value, to_llvm_type, partial)
      when 64 then gen_numeric_conv_f64_to_sint(value, to_llvm_type, partial)
      else raise NotImplementedError.new(from_width)
      end
    elsif from_float
      case from_width
      when 32 then gen_numeric_conv_f32_to_uint(value, to_llvm_type, partial)
      when 64 then gen_numeric_conv_f64_to_uint(value, to_llvm_type, partial)
      else raise NotImplementedError.new(from_width)
      end
    elsif from_signed && to_float
      @builder.si2fp(value, to_llvm_type)
    elsif to_float
      @builder.ui2fp(value, to_llvm_type)
    elsif partial
      gen_numeric_conv_integer_partial(
        value, to_llvm_type,
        from_width, to_width,
        from_signed, to_signed
      )
    elsif from_width > to_width
      @builder.trunc(value, to_llvm_type)
    elsif from_width < to_width
      if from_signed
        @builder.sext(value, to_llvm_type)
      else
        @builder.zext(value, to_llvm_type)
      end
    else
      value
    end
  end

  def gen_numeric_conv_float_handle_nan(
    value : LLVM::Value,
    int_type : LLVM::Type,
    exp : UInt64,
    mantissa : UInt64,
  )
    nan = gen_block("nan")
    non_nan = gen_block("non_nan")

    exp_mask = int_type.const_int(exp)
    mant_mask = int_type.const_int(mantissa)

    bits = @builder.bit_cast(value, int_type, "bits")
    exp_res = @builder.and(bits, exp_mask, "exp_res")
    mant_res = @builder.and(bits, mant_mask, "mant_res")

    exp_res = @builder.icmp(
      LLVM::IntPredicate::EQ, exp_res, exp_mask, "exp_res")
    mant_res = @builder.icmp(
      LLVM::IntPredicate::NE, mant_res, int_type.const_int(0), "mant_res")

    is_nan = @builder.and(exp_res, mant_res, "is_nan")
    @builder.cond(is_nan, nan, non_nan)
    finish_block_and_move_to(nan)

    return non_nan
  end

  def gen_numeric_conv_integer_partial(
    value : LLVM::Value,
    to_type : LLVM::Type,
    from_width : Int,
    to_width : Int,
    from_signed : Bool,
    to_signed : Bool,
  )
    if to_signed
      to_min = @builder.not(to_type.const_int(0), "to_min.pre")
      to_max = @builder.lshr(to_min, to_type.const_int(1), "to_max")
      to_min = @builder.xor(to_max, to_min, "to_min")
    else
      to_min = to_type.const_int(0)
      to_max = @builder.not(to_min, "to_max")
    end

    can_overflow = (
      (from_width > to_width) ||
      (from_width == to_width && !from_signed && to_signed)
    )
    can_underflow = from_signed && (
      (from_width > to_width) ||
      !to_signed
    )

    test_overflow = gen_block("test_overflow") if can_overflow
    test_underflow = gen_block("test_underflow") if can_underflow
    error = gen_block("error") if can_overflow || can_underflow
    normal = gen_block("normal")

    @builder.br(test_overflow || test_underflow || normal)

    # Generate the block that tests for overflow, if overflow is possible.
    if test_overflow
      finish_block_and_move_to(test_overflow)

      to_max_conv =
        if from_width > to_width
          @builder.zext(to_max, value.type)
        elsif from_width < to_width
          raise "this should never happen"
        else
          to_max
        end
      overflow_pred = from_signed ? LLVM::IntPredicate::SGT : LLVM::IntPredicate::UGT
      is_overflow = @builder.icmp(overflow_pred, value, to_max_conv)
      @builder.cond(is_overflow, error.not_nil!, test_underflow || normal)
    end

    # Generate the block that tests for underflow, if underflow is possible.
    if test_underflow
      finish_block_and_move_to(test_underflow)

      to_min_conv =
        if from_width > to_width
          @builder.sext(to_min, value.type)
        elsif from_width < to_width
          @builder.trunc(to_min, value.type)
        else
          to_min
        end
      is_underflow = @builder.icmp(LLVM::IntPredicate::SLT, value, to_min_conv)
      @builder.cond(is_underflow, error.not_nil!, normal)
    end

    # Generate the block that raises an error for overflow or underflow.
    if error
      finish_block_and_move_to(error)
      gen_raise_error(gen_none, nil)
    end

    # Otherwise, proceed with the conversion as normal.
    finish_block_and_move_to(normal)
    if from_width > to_width
      @builder.trunc(value, to_type)
    elsif from_width < to_width
      if from_signed
        @builder.sext(value, to_type)
      else
        @builder.zext(value, to_type)
      end
    else
      value
    end
  end

  def gen_numeric_conv_float_handle_overflow_saturate(
    value : LLVM::Value,
    from_type : LLVM::Type,
    to_type : LLVM::Type,
    to_min : LLVM::Value,
    to_max : LLVM::Value,
    is_signed : Bool,
    partial : Bool,
  )
    overflow = gen_block("overflow")
    test_underflow = gen_block("test_underflow")
    underflow = gen_block("underflow")
    normal = gen_block("normal")

    # Check if the floating-point value overflows the maximum integer value.
    to_fmax =
      if is_signed
        @builder.si2fp(to_max, from_type)
      else
        @builder.ui2fp(to_max, from_type)
      end
    is_overflow = @builder.fcmp(LLVM::RealPredicate::OGT, value, to_fmax)
    @builder.cond(is_overflow, overflow, test_underflow)

    # If it does overflow, return the maximum integer value.
    finish_block_and_move_to(overflow)
    if partial
      gen_raise_error(gen_none, nil)
    else
      gen_return_value(to_max, nil)
    end

    # Check if the floating-point value underflows the minimum integer value.
    finish_block_and_move_to(test_underflow)
    to_fmin =
      if is_signed
        @builder.si2fp(to_min, from_type)
      else
        @builder.ui2fp(to_min, from_type)
      end
    is_underflow = @builder.fcmp(LLVM::RealPredicate::OLT, value, to_fmin)
    @builder.cond(is_underflow, underflow, normal)

    # If it does underflow, return the minimum integer value.
    finish_block_and_move_to(underflow)
    if partial
      gen_raise_error(gen_none, nil)
    else
      gen_return_value(to_min, nil)
    end

    # Otherwise, proceed with the conversion as normal.
    finish_block_and_move_to(normal)
    if is_signed
      @builder.fp2si(value, to_type)
    else
      @builder.fp2ui(value, to_type)
    end
  end

  def gen_numeric_conv_f64_to_f32(value : LLVM::Value, partial : Bool)
    # If the value is F64 NaN, return F32 NaN.
    test_overflow = gen_numeric_conv_float_handle_nan(
      value, @i64, 0x7ff0000000000000, 0x000fffffffffffff)
    gen_return_value(@llvm.const_bit_cast(@i32.const_int(0x7fc00000), @f32), nil)

    overflow = gen_block("overflow")
    test_underflow = gen_block("test_underflow")
    underflow = gen_block("underflow")
    normal = gen_block("normal")

    # Check if the F64 value overflows the maximum F32 value.
    finish_block_and_move_to(test_overflow)
    f32_max = @llvm.const_bit_cast(@i32.const_int(0x7f7fffff), @f32)
    f32_max = @builder.fpext(f32_max, @f64, "f32_max")
    is_overflow = @builder.fcmp(LLVM::RealPredicate::OGT, value, f32_max)
    @builder.cond(is_overflow, overflow, test_underflow)

    # If it does overflow, return positive infinity or raise error if partial.
    finish_block_and_move_to(overflow)
    if partial
      gen_raise_error(gen_none, nil)
    else
      gen_return_value(@llvm.const_bit_cast(@i32.const_int(0x7f800000), @f32), nil)
    end

    # Check if the F64 value underflows the minimum F32 value.
    finish_block_and_move_to(test_underflow)
    f32_min = @llvm.const_bit_cast(@i32.const_int(0xff7fffff), @f32)
    f32_min = @builder.fpext(f32_min, @f64, "f32_min")
    is_underflow = @builder.fcmp(LLVM::RealPredicate::OLT, value, f32_min)
    @builder.cond(is_underflow, underflow, normal)

    # If it does underflow, return negative infinity or raise error if partial.
    finish_block_and_move_to(underflow)
    if partial
      gen_raise_error(gen_none, nil)
    else
      gen_return_value(@llvm.const_bit_cast(@i32.const_int(0xff800000), @f32), nil)
    end

    # Otherwise, proceed with the floating-point truncation as normal.
    finish_block_and_move_to(normal)
    @builder.fptrunc(value, @f32)
  end

  def gen_numeric_conv_f32_to_sint(value : LLVM::Value, to_type : LLVM::Type, partial : Bool)
    test_overflow = gen_numeric_conv_float_handle_nan(
      value, @i32, 0x7f800000, 0x007fffff)
    if partial
      gen_raise_error(gen_none, nil)
    else
      gen_return_value(to_type.const_int(0), nil)
    end

    finish_block_and_move_to(test_overflow)
    to_min = @builder.not(to_type.const_int(0), "to_min.pre")
    to_max = @builder.lshr(to_min, to_type.const_int(1), "to_max")
    to_min = @builder.xor(to_max, to_min, "to_min")
    gen_numeric_conv_float_handle_overflow_saturate(
      value, @f32, to_type, to_min, to_max, is_signed: true, partial: partial)
  end

  def gen_numeric_conv_f64_to_sint(value : LLVM::Value, to_type : LLVM::Type, partial : Bool)
    test_overflow = gen_numeric_conv_float_handle_nan(
      value, @i64, 0x7ff0000000000000, 0x000fffffffffffff)
    if partial
      gen_raise_error(gen_none, nil)
    else
      gen_return_value(to_type.const_int(0), nil)
    end

    finish_block_and_move_to(test_overflow)
    to_min = @builder.not(to_type.const_int(0), "to_min.pre")
    to_max = @builder.lshr(to_min, to_type.const_int(1), "to_max")
    to_min = @builder.xor(to_max, to_min, "to_min")
    gen_numeric_conv_float_handle_overflow_saturate(
      value, @f64, to_type, to_min, to_max, is_signed: true, partial: partial)
  end

  def gen_numeric_conv_f32_to_uint(value : LLVM::Value, to_type : LLVM::Type, partial : Bool)
    test_overflow = gen_numeric_conv_float_handle_nan(
      value, @i32, 0x7f800000, 0x007fffff)
    if partial
      gen_raise_error(gen_none, nil)
    else
      gen_return_value(to_type.const_int(0), nil)
    end

    finish_block_and_move_to(test_overflow)
    to_min = to_type.const_int(0)
    to_max = @builder.not(to_min, "to_max")
    gen_numeric_conv_float_handle_overflow_saturate(
      value, @f32, to_type, to_min, to_max, is_signed: false, partial: partial)
  end

  def gen_numeric_conv_f64_to_uint(value : LLVM::Value, to_type : LLVM::Type, partial : Bool)
    test_overflow = gen_numeric_conv_float_handle_nan(
      value, @i64, 0x7ff0000000000000, 0x000fffffffffffff)
    if partial
      gen_raise_error(gen_none, nil)
    else
      gen_return_value(to_type.const_int(0), nil)
    end

    finish_block_and_move_to(test_overflow)
    to_min = to_type.const_int(0)
    to_max = @builder.not(to_min, "to_max")
    gen_numeric_conv_float_handle_overflow_saturate(
      value, @f64, to_type, to_min, to_max, is_signed: false, partial: partial)
  end

  def gen_global_for_const(const : LLVM::Value, name : String = "") : LLVM::Value
    global = @mod.globals.add(const.type, name)
    global.linkage = LLVM::Linkage::Private
    global.initializer = const
    global.global_constant = true
    global.unnamed_addr = true
    global
  end

  def gen_const_for_gtype(gtype : GenType, values : Hash(String, LLVM::Value))
    pad_elements =
      gtype.struct_type
        .struct_element_types[1...-1]
        .map(&.null)

    fields = gtype.fields_struct_type.const_struct(
      gtype.fields.map(&.first).map { |name| values[name] }
    )

    gtype.struct_type.const_struct([gtype.desc] + pad_elements + [fields])
  end

  def gen_global_const(*args)
    gen_global_for_const(gen_const_for_gtype(*args))
  end

  def gen_cstring(value : String) : LLVM::Value
    @llvm.const_inbounds_gep(
      @ptr,
      @cstring_globals.fetch value do
        global = gen_global_for_const(@llvm.const_string(value))

        @cstring_globals[value] = global
      end,
      [@i32_0, @i32_0],
    )
  end

  def gen_string(value : String)
    @string_globals.fetch value do
      global = gen_global_const(@gtypes["String"], {
        "_size"  => @isize.const_int(value.bytesize),
        "_space" => @isize.const_int(value.bytesize + 1),
        "_ptr"   => gen_cstring(value),
      })

      @string_globals[value] = global
    end
  end

  def gen_bstring(value : String)
    @bstring_globals.fetch value do
      global = gen_global_const(@gtypes["Bytes"], {
        "_size"  => @isize.const_int(value.bytesize),
        "_space" => @isize.const_int(value.bytesize + 1),
        "_ptr"   => gen_cstring(value),
      })

      @bstring_globals[value] = global
    end
  end

  def gen_array(array_gtype, values : Array(LLVM::Value)) : LLVM::Value
    if values.size > 0
      values_type = values.first.type # assume all values have the same LLVM::Type
      values_global = gen_global_for_const(values_type.const_array(values))

      gen_global_const(array_gtype, {
        "_size"  => @isize.const_int(values.size),
        "_space" => @isize.const_int(values.size),
        "_ptr"   => @llvm.const_inbounds_gep(@ptr, values_global, [@i32_0, @i32_0])
      })
    else
      gen_global_const(array_gtype, {
        "_size"  => @isize.const_int(0),
        "_space" => @isize.const_int(0),
        "_ptr"   => @ptr.null
      })
    end
  end

  def gen_source_code_pos(pos : Source::Pos)
    @source_code_pos_globals.fetch pos do
      global = gen_global_const(@gtypes["SourceCodePosition"], {
        "string"  => gen_string(pos.content),
        "filename"=> gen_string(pos.source.filename),
        "dirname" => gen_string(pos.source.dirname),
        "pkgname" => gen_string(pos.source.package.name),
        "pkgpath" => gen_string(pos.source.package.path),
        "row"     => @isize.const_int(pos.row),
        "col"     => @isize.const_int(pos.col),
        "filepath_pkgrel" => gen_string(pos.source.filepath_relative_to_package),
        "filepath_rootpkgrel" => gen_string((Path.new(pos.source.dirname).relative_to(
          Path.new(@ctx.not_nil!.root_package_link.path)) / pos.source.filename).to_s)
      })

      @source_code_pos_globals[pos] = global
    end
  end

  def gen_stack_address_of_variable(expr, term_expr)
    ref = func_frame.refer[term_expr].as Refer::Local

    alloca = func_frame.current_locals[ref]

    alloca
  end

  def gen_static_address_of_function(expr : AST::Relate) : LLVM::Value
    receiver = gen_expr(expr.lhs)

    gtype, gfunc = resolve_call(
      AST::Call.new(expr.lhs, expr.rhs.as(AST::Identifier)).from(expr)
    )

    gfunc.llvm_func.to_value
  end

  def gen_reflection_of_type(expr, term_expr)
    reflect_gtype = gtype_of(expr)

    @reflection_of_type_globals.fetch reflect_gtype do
      reach_ref = type_of(term_expr)

      props = {} of String => LLVM::Value
      props["string"] = gen_string(reach_ref.show_type)

      if reflect_gtype.field?("features")
        features_gtype = gtype_of(reflect_gtype.field("features"))
        feature_gtype = gtype_of(
          features_gtype.field("_ptr")
            .single_def!(ctx).cpointer_type_arg(ctx)
        )
        mutator_gtype = gtype_of(
          feature_gtype.field("mutator")
            .union_children.find(&.show_type.!=("None")).not_nil!
        )

        raise NotImplementedError.new(reach_ref.show_type) \
          unless reach_ref.singular?
        gtype = gtype_of(reach_ref)

        features =
          gtype.gfuncs.values
            .reject(&.func.has_tag?(:hygienic))
            .reject(&.func.ident.value.starts_with?("_"))
            .map do |gfunc|
              tags = gfunc.func.tags_sorted.map { |tag| gen_string(tag.to_s) }

              # A mutator must meet the following qualifications:
              # a ref function that takes no arguments and returns None.
              # Any other function can't be safely called this way, so we
              # leave its mutator field as None so that it can't be called.
              # In the future, we may make it possible to call other functions
              # that are not mutators, but that becomes a tough type system
              # problem to solve, not the least of which is type variable varargs.
              mutator =
                if gfunc.func.cap.value == "ref" \
                && (gfunc.func.params.try(&.terms.size) || 0) == 0 \
                && gfunc.reach_func.signature.ret.is_none?
                  gen_reflection_mutator_of_type(mutator_gtype, gtype, gfunc)
                else
                  gen_none
                end

              gen_global_const(feature_gtype, {
                "name" => gen_string(gfunc.func.ident.value),
                "tags" => gen_array(@gtypes["Array[String]"], tags),
                "mutator" => mutator,
              })
            end

        props["features"] = gen_array(features_gtype, features)
      end

      global = gen_global_const(reflect_gtype, props)

      @reflection_of_type_globals[reflect_gtype] = global
    end
  end

  def gen_reflection_mutator_of_type(mutator_gtype, gtype, gfunc)
    mutator_call_gfunc = mutator_gtype.gfuncs["call"]

    # This code is shamelessly copied from gen_desc, with a few modifications,
    # because we already know that we are just targeting exactly one gtype
    # (the mutator_gtype which this object is tailor-made to fit).
    traits_bitmap = trait_bitmap_size.times.map { 0 }.to_a
    mutator_gtype.type_def.tap do |other_def|
      raise "can't be subtype of a concrete" unless other_def.is_abstract?(ctx)

      index = other_def.desc_id >> Math.log2(@bitwidth).to_i
      raise "bad index or trait_bitmap_size" unless index < trait_bitmap_size

      bit = other_def.desc_id & (@bitwidth - 1)
      traits_bitmap[index] |= (1 << bit)
    end
    traits_bitmap_global = gen_global_for_const \
      @isize.const_array(traits_bitmap.map { |bits| @isize.const_int(bits) })

    # Create an intermediary function that strips the mutator_gtype receiver
    # from the arguments forwarded to the gfunc we actually want to call.
    orig_block = @builder.insert_block.not_nil!
    @builder.clear_insertion_position

    via_llvm_func =
      gen_llvm_func(
        "#{gfunc.llvm_name}.VIA.#{mutator_gtype.type_def.llvm_name}",
        mutator_call_gfunc.virtual_llvm_func.function_type.params_types,
        mutator_call_gfunc.virtual_llvm_func.function_type.return_type,
      ) do |fn|
        gen_func_start(fn)
        @builder.ret @builder.call(
          gfunc.llvm_func.function_type,
          gfunc.llvm_func,
          [fn.params[1]]
        )
        gen_func_end
      end

    # Go back to the original block that we were at before making this function.
    finish_block_and_move_to(orig_block)

    # Create a vtable that places our via function in the proper index.
    vtable = mutator_gtype.gen_vtable(self)
    vtable[mutator_call_gfunc.vtable_index] = via_llvm_func.to_value

    # Save the name of the mutator gtype's type_def as a proper String,
    # casting it to an opaque pointer to avoid circular dependency on descs.
    type_name_string = gen_string(mutator_gtype.type_def.llvm_name)

    # Generate a type descriptor, so this can masquerade as a real module.
    raise NotImplementedError.new("gen_reflection_mutator_of_type in Verona") \
      if @runtime.is_a?(VeronaRT)
    desc = gen_global_for_const(mutator_gtype.desc_type.const_struct [
      @i32.const_int(0xffff_ffff),         # 0: id
      @i32.const_int(abi_size_of(@ptr)),   # 1: size
      @i32_0,                              # 2: field_count (tuples only)
      @i32_0,                              # 3: field_offset
      @obj_ptr.null,                       # 4: instance
      @trace_fn_ptr.null,                  # 5: trace fn
      @trace_fn_ptr.null,                  # 6: serialise trace fn
      @serialise_fn_ptr.null,              # 7: serialise fn
      @deserialise_fn_ptr.null,            # 8: deserialise fn
      @custom_serialise_space_fn_ptr.null, # 9: custom serialise space fn
      @custom_deserialise_fn_ptr.null,     # 10: custom deserialise fn
      @dispatch_fn_ptr.null,               # 11: dispatch fn
      @final_fn_ptr.null,                  # 12: final fn
      @i32.const_int(-1),                  # 13: event notify
      traits_bitmap_global,                # 14: traits bitmap
      type_name_string,                    # 15: type name (REPLACES unused field descriptors from Pony)
      @ptr.const_array(vtable),            # 16: vtable
    ])

    # Finally, create the singleton "instance" for this fake primitve.
    gen_global_for_const(@obj.const_struct([desc]))
  end

  def gen_reflection_of_runtime_type_name(expr, term_expr)
    value = gen_expr(term_expr)
    value_type = value.type

    desc =
      if value_type.kind == LLVM::Type::Kind::Pointer
        # This has an object header, so we can get the descriptor at runtime.
        gen_get_desc(value)
      else
        # Otherwise this is an unboxed machine word value with no descriptor,
        # and we need to get the descriptor at compile time instead.
        gtype_of(term_expr).desc
      end

    @runtime.gen_type_name_get(self, desc, "#{value.name}.DESC.TYPE_NAME")
  end

  def gen_sequence(expr : AST::Group)
    # Use None as a value when the sequence group size is zero.
    if expr.terms.size == 0
      type_of(expr).is_none!
      return gen_none
    end

    # TODO: Push a scope frame?

    final : LLVM::Value? = nil
    expr.terms.each { |term| final = gen_expr(term) }
    final.not_nil!

    # TODO: Pop the scope frame?
  end

  def gen_dynamic_array(expr : AST::Group) : LLVM::Value
    gtype = gtype_of(expr)

    # If this array expression is inside of a constant, we know that it has
    # been typechecked to be a constant expression and can generate it as such.
    # TODO: Is it possible to determine that other array expressions in other
    # code snippets are safe to be lifted to constant expressions?
    if func_frame.gfunc.try(&.func.has_tag?(:constant))
      return gen_array(gtype, expr.terms.map { |term| gen_expr(term) })
    end

    receiver = gen_alloc(gtype, expr, "#{gtype.type_def.llvm_name}.new")
    size_arg = @i64.const_int(expr.terms.size)
    @builder.call(
      gtype.default_constructor.llvm_func.function_type,
      gtype.default_constructor.llvm_func,
      [receiver, size_arg],
    )

    arg_type = gtype.gfuncs["<<"].reach_func.signature.params.first

    expr.terms.each do |term|
      value = gen_assign_cast(gen_expr(term), arg_type, nil, term)
      @builder.call(
        gtype.gfuncs["<<"].llvm_func.function_type,
        gtype.gfuncs["<<"].llvm_func,
        [receiver, value]
      )
    end

    receiver
  end

  # TODO: Use infer resolution for static True/False finding where possible.
  def gen_choice(expr : AST::Choice)
    raise NotImplementedError.new(expr.inspect) if expr.list.empty?

    phi_type = nil

    # Create all of the instruction blocks we'll need for this choice.
    j = expr.list.size
    case_and_cond_blocks = [] of LLVM::BasicBlock
    expr.list.each_cons(2).to_a.each_with_index do |(fore, aft), i|
      case_and_cond_blocks << gen_block("case#{i + 1}of#{j}_choice")
      case_and_cond_blocks << gen_block("cond#{i + 2}of#{j}_choice")
    end
    case_and_cond_blocks << gen_block("case#{j}of#{j}_choice")
    post_block = gen_block("after#{j}of#{j}_choice")

    # Generate code for the first condition - we always start by running this.
    cond_value = gen_as_cond(gen_expr(expr.list.first[0]))

    # Generate the interacting code for each consecutive pair of cases.
    phi_blocks = [] of LLVM::BasicBlock
    phi_values = [] of LLVM::Value
    expr.list.each_cons(2).to_a.each_with_index do |(fore, aft), i|
      # The case block is the body to execute if the cond_value is true.
      # Otherwise we will jump to the next block, with its next cond_value.
      case_block = case_and_cond_blocks.shift
      next_block = case_and_cond_blocks.shift
      @builder.cond(cond_value, case_block, next_block)

      finish_block_and_move_to(case_block)
      if meta_type_unconstrained?(fore[1]) && !func_frame.flow.jumps_away?(fore[1])
        # We skip generating code for the case block if it is unreachable,
        # meaning that the cond was deemed at compile time to never be true.
        # This is marked by an unconstrained result MetaType, provided that
        # the block does not jump away (which is also unconstrained).
        @builder.unreachable
      else
        # Generate code for the case block that we execute, finishing by
        # jumping to the post block using the `br` instruction, where we will
        # carry the value we just generated as one of the possible phi values.
        value = gen_expr(fore[1])
        unless func_frame.flow.jumps_away?(fore[1])
          if func_frame.classify.value_needed?(expr)
            phi_type ||= type_of(expr)
            value = gen_assign_cast(value, phi_type.not_nil!, nil, fore[1])
            phi_blocks << @builder.insert_block.not_nil!
            phi_values << value
          end
          @builder.br(post_block)
        end
      end

      # Generate code for the next block, which is the condition to be
      # checked for truthiness in the next iteration of this loop
      # (or ignored if this is the final case, which must always be exhaustive).
      finish_block_and_move_to(next_block)
      cond_value = gen_expr(aft[0])
    end

    # This is the final case block - we will jump to it unconditionally,
    # regardless of the truthiness of the preceding cond_value.
    # Choices must always be typechecked to be exhaustive, so we can rest
    # on the guarantee that this cond_value will always be true if we reach it.
    case_block = case_and_cond_blocks.shift
    @builder.br(case_block)

    finish_block_and_move_to(case_block)
    if meta_type_unconstrained?(expr.list.last[1]) && !func_frame.flow.jumps_away?(expr.list.last[1])
      # We skip generating code for the case block if it is unreachable,
      # meaning that the cond was deemed at compile time to never be true.
      # This is marked by an unconstrained result MetaType, provided that
      # the block does not jump away (which is also unconstrained).
      @builder.unreachable
    else
      # Generate code for the final case block using exactly the same strategy
      # that we used when we generated case blocks inside the loop above.
      value = gen_expr(expr.list.last[1])
      unless func_frame.flow.jumps_away?(expr.list.last[1])
        if func_frame.classify.value_needed?(expr)
          phi_type ||= type_of(expr)
          value = gen_assign_cast(value, phi_type.not_nil!, nil, expr.list.last[1])
          phi_blocks << @builder.insert_block.not_nil!
          phi_values << value
        end
        @builder.br(post_block)
      end
    end

    # When we jump away, we can't generate the post block.
    if func_frame.flow.jumps_away?(expr)
      post_block.delete
      return gen_none
    end

    # Here at the post block, we receive the value that was returned by one of
    # the cases above, using the LLVM mechanism called a "phi" instruction.
    finish_block_and_move_to(post_block)
    if func_frame.classify.value_needed?(expr)
      @builder.phi(llvm_type_of(phi_type.not_nil!), phi_blocks, phi_values, "phi_choice")
    else
      gen_none
    end
  end

  def gen_loop(expr : AST::Loop)
    # Get the LLVM type for the phi that joins the final value of each branch.
    # Each such value will needed to be bitcast to the that type.
    phi_type = type_of_unless_unsatisfiable(expr) || @gtypes["None"].type_def.as_ref

    # check if we have any early continues to not to generate continue block
    pre_infer = ctx.pre_infer[func_frame.gfunc.not_nil!.link]
    has_nexts = !pre_infer[expr].as(Infer::Loop).early_nexts.empty?

    # Prepare to capture state for the final phi.
    phi_blocks = [] of LLVM::BasicBlock
    phi_values = [] of LLVM::Value

    # Create all of the instruction blocks we'll need for this loop.
    body_block = gen_block("body_loop")
    next_block = gen_block("next_loop") if has_nexts
    else_block = gen_block("else_loop")
    post_block = gen_block("after_loop")

    @loop_next_stack << {
      next_block,
      [] of LLVM::BasicBlock,
      [] of LLVM::Value,
      phi_type.not_nil!,
    } if next_block
    @loop_break_stack << {
      post_block,
      [] of LLVM::BasicBlock,
      [] of LLVM::Value,
      phi_type.not_nil!,
    }

    # Start by generating the code to test the condition value.
    # If the cond is true, go to the body block; otherwise, the else block.
    cond_value = gen_as_cond(gen_expr(expr.initial_cond))
    @builder.cond(cond_value, body_block, else_block)

    # In the body block, generate code to arrive at the body value,
    # and also generate the condition value code again.
    # If the cond is true, repeat the body block; otherwise, go to post block.
    finish_block_and_move_to(body_block)
    body_value = gen_expr(expr.body)

    unless func_frame.flow.jumps_away?(expr.body)
      cond_value = gen_as_cond(gen_expr(expr.repeat_cond))

      if func_frame.classify.value_needed?(expr)
        body_value = gen_assign_cast(body_value, phi_type, nil, expr.body)
        phi_blocks << @builder.insert_block.not_nil!
        phi_values << body_value
      end
      @builder.cond(cond_value, body_block, post_block)
    end

    if next_block
      next_stack_tuple = @loop_next_stack.pop
      raise "invalid post next stack" \
        unless next_stack_tuple[0] == next_block

      finish_block_and_move_to(next_block)
      next_value =
        @builder.phi(
          llvm_type_of(phi_type.not_nil!),
          next_stack_tuple[1],
          next_stack_tuple[2],
          "next_expression_value",
        )
      cond_value = gen_as_cond(gen_expr(expr.repeat_cond))
      phi_blocks << @builder.insert_block.not_nil!
      phi_values << next_value
      @builder.cond(cond_value, body_block, post_block)
    end

    break_stack_tuple = @loop_break_stack.pop
    raise "invalid post break stack" \
      unless break_stack_tuple[0] == post_block

    # In the body block, generate code to arrive at the else value,
    # Then skip straight to the post block.
    finish_block_and_move_to(else_block)
    else_value = gen_expr(expr.else_body)
    unless func_frame.flow.jumps_away?(expr.else_body)
      if func_frame.classify.value_needed?(expr)
        else_value = gen_assign_cast(else_value, phi_type, nil, expr.else_body)
        phi_blocks << @builder.insert_block.not_nil!
        phi_values << else_value
      end
      @builder.br(post_block)
    end

    # When we jump away, we can't generate the post block.
    if func_frame.flow.jumps_away?(expr)
      post_block.delete
      return gen_none
    end

    # Here at the post block, we receive the value that was returned by one of
    # the bodies above, using the LLVM mechanism called a "phi" instruction.
    finish_block_and_move_to(post_block)
    if func_frame.classify.value_needed?(expr)
      @builder.phi(
        llvm_type_of(phi_type),
        phi_blocks + break_stack_tuple[1],
        phi_values + break_stack_tuple[2],
        "phi_loop",
      )
    else
      gen_none
    end
  end

  def gen_try(expr : AST::Try)
    # Prepare to capture state for the final phi.
    phi_type = nil
    phi_blocks = [] of LLVM::BasicBlock
    phi_values = [] of LLVM::Value

    # Create all of the instruction blocks we'll need for this try.
    body_block = gen_block("body_try")
    else_block = gen_block("else_try")
    post_block = gen_block("after_try")
    @try_else_stack << {else_block, [] of LLVM::BasicBlock, [] of LLVM::Value}

    # Go straight to the body block from whatever block we are in now.
    @builder.br(body_block)

    # Generate the body and get the resulting value, assuming no throw happened.
    # Then continue to the post block.
    finish_block_and_move_to(body_block)
    body_value = gen_expr(expr.body)
    unless func_frame.flow.jumps_away?(expr.body)
      phi_type ||= type_of(expr)
      body_value = gen_assign_cast(body_value, phi_type.not_nil!, nil, expr.body)
      phi_blocks << @builder.insert_block.not_nil!
      phi_values << body_value
      @builder.br(post_block)
    end

    # Now start generating the else clause (reached when a throw happened).
    finish_block_and_move_to(else_block)

    # TODO: Allow an error_phi_llvm_type of something other than None.
    error_phi_llvm_type = llvm_type_of(@gtypes["None"])

    else_stack_tuple = @try_else_stack.pop
    raise "invalid try else stack" unless else_stack_tuple[0] == else_block
    if else_stack_tuple[1].empty?
      # If the else stack tuple has empty predecessors, this is a try block
      # that has no possibility of ever throwing an error.
      # So we mark the else block as being unreachable, and skip generating it.
      @builder.unreachable
    else
      # Catch the thrown error value, by getting the blocks and values from the
      # try_else_stack and using the LLVM mechanism called a "phi" instruction.
      error_value = @builder.phi(
        error_phi_llvm_type,
        else_stack_tuple[1],
        else_stack_tuple[2],
        "phi_else_try",
      )

      # TODO: allow the else block to reference the error value as a local.

      # Generate the body code of the else clause, then proceed to the post block.
      else_value = gen_expr(expr.else_body)
      unless func_frame.flow.jumps_away?(expr.else_body)
        phi_type ||= type_of(expr)
        else_value = gen_assign_cast(else_value, phi_type.not_nil!, nil, expr.else_body)
        phi_blocks << @builder.insert_block.not_nil!
        phi_values << else_value
        @builder.br(post_block)
      end
    end

    # We can't have a phi with no predecessors, so we don't generate it, and
    # return a None value; it won't be used, but this method can't return nil.
    if phi_blocks.empty? && phi_values.empty?
      post_block.delete
      return gen_none
    end

    # Here at the post block, we receive the value that was returned by one of
    # the bodies above, using the LLVM mechanism called a "phi" instruction.
    finish_block_and_move_to(post_block)
    @builder.phi(llvm_type_of(phi_type.not_nil!), phi_blocks, phi_values, "phi_try")
  end

  def gen_return_value(value : LLVM::Value, from_expr : AST::Node?)
    gfunc = func_frame.gfunc.not_nil!
    gfunc.calling_convention.gen_return(self, gfunc, value, from_expr)
    .tap { finish_block_and_move_to(gen_block("unreachable_after_early_return")) }
  end

  def gen_raise_error(error_value : LLVM::Value, from_expr : AST::Node?)
    raise "inconsistent frames" if @frames.size > 1

    # error_value now is generated properly from the error! argument
    # but we need to replace it with None for now
    # TODO: Allow an error value of something other than None.
    error_value = gen_none

    # If we have no local try to catch the value, then we return it
    # using the error return approach for this calling convention.
    if @try_else_stack.empty?
      gfunc = func_frame.gfunc.not_nil!
      gfunc.calling_convention.gen_error_return(self, gfunc, error_value, from_expr)
      .tap { finish_block_and_move_to(gen_block("unreachable_after_error_return")) }
    else
      # Store the state needed to catch the value in the try else block.
      else_stack_tuple = @try_else_stack.last
      else_stack_tuple[1] << @builder.insert_block.not_nil!
      else_stack_tuple[2] << error_value

      # Jump to the try else block.
      @builder.br(else_stack_tuple[0])
      .tap { finish_block_and_move_to(gen_block("unreachable_after_error")) }
    end
  end

  def gen_next(value : LLVM::Value, from_expr : AST::Node)
    raise NotImplementedError.new("inconsistent stack") if @loop_next_stack.empty?

    next_stack_tuple = @loop_next_stack.last.not_nil!
    typ = next_stack_tuple[3]
    next_stack_tuple[1] << @builder.insert_block.not_nil!
    next_stack_tuple[2] << gen_assign_cast(value, typ, nil, from_expr)

    @builder.br(next_stack_tuple[0])
    .tap { finish_block_and_move_to(gen_block("unreachable_after_next")) }
  end

  def gen_break_loop(value : LLVM::Value, from_expr : AST::Node)
    raise NotImplementedError.new("inconsistent stack") if @loop_break_stack.empty?

    break_stack_tuple = @loop_break_stack.last.not_nil!
    typ = break_stack_tuple[3]
    break_stack_tuple[1] << @builder.insert_block.not_nil!
    break_stack_tuple[2] << gen_assign_cast(value, typ, nil, from_expr)

    @builder.br(break_stack_tuple[0])
    .tap { finish_block_and_move_to(gen_block("unreachable_after_break")) }
  end

  def gen_yield(expr : AST::Yield)
    raise "inconsistent frames" if @frames.size > 1

    @di.set_loc(expr)

    gfunc = func_frame.gfunc.not_nil!

    # First, we must know which yield this is in the function -
    # each yield expression has a uniquely associated index.
    all_yields = ctx.inventory[gfunc.link].each_yield.to_a
    yield_index = all_yields.index(expr).not_nil!
    after_block = gfunc.after_yield_blocks[yield_index]

    # If this after_block is already taken, we need to find the next one
    # that matches our expression. This can happen in cases when a block
    # of code can be generated and executed in multiple contexts. For example,
    # this happens in the initial_cond and repeat_cond of a `while` macro,
    # which uses the same AST tree for both condition expressions.
    until after_block.instructions.empty?
      yield_index += 1 + all_yields[(yield_index + 1)..-1].index(expr).not_nil!
      after_block = gfunc.after_yield_blocks[yield_index]
    end

    # Generate code for the values of the yield, and capture the values.
    yield_values = expr.terms.map { |term| gen_expr(term) }

    # Capture the current value of each local variable, because we store every
    # local not only in the continuation but also in its own dedicated alloca.
    # Thus we need to load the current alloca values into the continuation
    # before yielding, as the allocas will be popped off the stack on yield.
    # Obviously this is redundant and not strictly necessary to store every
    # value in two places, but the extra alloca makes debugging nice, since lldb
    # doesn't seem to understand how to access non-alloca local variables.
    # So we redundantly store in two places, and we count on LLVM optimization
    # to get rid of either one of the two redundant stores, as it sees fit.
    # Note that we really hope it will keep the alloca and get rid of
    # the continuation struct when it inlines the yielding call,
    # but this can't always happen (e.g. for recursive yielding calls).
    ctx.inventory[gfunc.link].each_local.each_with_index do |ref, ref_index|
      cont = func_frame.continuation_value
      cont_local =
        gfunc.continuation_info.struct_gep_for_local(cont, ref)
      local = frame.current_locals[ref]
      local_llvm_type = llvm_type_of(func_frame.any_defn_for_local(ref))

      @builder.store(
        builder.load(local_llvm_type, local, "#{ref.name}.CURRENT"),
        cont_local,
      )
    end

    # Generate the return statement, which terminates this basic block and
    # returns the tuple of the yield value and continuation data to the caller.
    gfunc.calling_convention
      .gen_yield_return(self, gfunc, yield_index, yield_values, expr.terms)

    # Now start generating the code that comes after the yield expression.
    # Note that this code block will be dead code (with "no predecessors")
    # in all but one of the continue functions that we generate - the one
    # continue function we grabbed above (which jumps to this block on entry).
    finish_block_and_move_to(after_block)

    # Finally, use the "yield in" value returned from the caller.
    # However, if we're not actually in a continuation function, then this
    # "yield in" value won't be present in the parameters and we need to
    # create an undefined value of the right type to fake it; but fear not,
    # that junk value won't be used because that code won't ever be reached.
    if gfunc.continue_llvm_func == func_frame.llvm_func
      yield_in_param_index = 1
      yield_in_param_index += 1 if gfunc.needs_receiver?
      func_frame.llvm_func.params[yield_in_param_index]
    else
      gfunc.continuation_info.yield_in_llvm_type.undef
    end
  end

  def gen_error_return_using_yield_cc
    raise "inconsistent frames" if @frames.size > 1
    gfunc = func_frame.gfunc.not_nil!

    # Grab the continuation value from local memory and mark it as an error.
    cont = func_frame.continuation_value
    gfunc.continuation_info.set_as_error(cont)

    # Return void.
    @builder.ret
  end

  def gen_struct_bit_cast(value : LLVM::Value, to_type : LLVM::Type)
    # LLVM doesn't allow directly casting to/from structs, so we cheat a bit
    # with an alloca in between the two as a pointer that we can cast.
    alloca = gen_alloca(value.type, "#{value.name}.PTR")
    @builder.store(value, alloca)
    @builder.load(to_type, alloca, "#{value.name}.CAST")
  end

  # Create an alloca at the entry block then return us back to whence we came.
  def gen_alloca(llvm_type : LLVM::Type, name : String)
    gen_at_entry do
      @builder.alloca(llvm_type, name)
    end
  end

  def gen_at_entry
    # We need to take note of the current block first, then move to the
    # entry block for inserting whatever we want to insert here.
    # We usually have to do this because otherwise we might accidentally create
    # something in a block and reuse it from another block that does not
    # follow the first block, resulting in invalid IR ("does not dominate").
    # All blocks follow the entry block (it dominates all other blocks),
    # so this is a surefire safe place to do whatever it is we need to declare.
    orig_block = @builder.insert_block.not_nil!
    entry_block = gen_frame.entry_block

    if entry_block.instructions.empty?
      @builder.position_at_end(entry_block)
    else
      @builder.position_before(entry_block.instructions.first)
    end

    # Let the caller declare what they may
    result = yield

    # Go back to the original block that we were at before this function.
    @builder.position_at_end(orig_block)

    # Return the result of the yielded block.
    result
  end

  # This defines a more specific struct type than the above function,
  # tailored to the specific type definition and its virtual table size.
  # The actual type descriptor value for the type is an instance of this.
  def gen_desc_type(type_def : Reach::Def, vtable_size : Int32) : LLVM::Type
    @runtime.gen_desc_type(self, type_def, vtable_size)
  end

  # This defines a global constant for the type descriptor of a type,
  # which is held as the first value in an object, used for identifying its
  # type at runtime, as well as a host of other functions related to dealing
  # with objects in the runtime, such as allocating them and tracing them.
  def gen_desc(gtype)
    @runtime.gen_desc(self, gtype)
  end

  # This populates the descriptor for the given type with its initialized data.
  def gen_desc_init(gtype, vtable)
    @runtime.gen_desc_init(self, gtype, vtable)
  end

  # This defines the LLVM struct type for objects of this type.
  def gen_struct_type(gtype)
    field_types = gtype.fields.map { |name, t| llvm_mem_type_of(t) }
    gtype.fields_struct_type.struct_set_body(field_types)

    @runtime.gen_struct_type(self, gtype)
  end

  # This defines the global singleton stateless value associated with this type.
  # This value is invoked whenever you reference the type with as a `non`,
  # acting as a runtime representation of a type itself rather than an instance.
  # For modules, this is the only value you'll ever see.
  def gen_singleton(gtype)
    global = @mod.globals.add(gtype.struct_type, gtype.type_def.llvm_name)
    global.linkage = LLVM::Linkage::Private
    global.global_constant = true

    # The first element is always the type descriptor.
    elements = [gtype.desc]

    # For allocated types, we still generate a singleton for static use, but
    # we need to populate the fields and padding with something - we use zeros.
    # We are relying on the reference capabilities part of the type system
    # to prevent such singletons from ever having their padding dereferenced.
    gtype.struct_type.struct_element_types[1..-1].map(&.null).each { |pad|
      elements << pad
    }

    global.initializer = gtype.struct_type.const_struct(elements)
    global
  end

  # This generates the code that allocates an object of the given type.
  # This is the first step before actually calling the constructor of it.
  def gen_alloc(gtype : GenType, from_expr : AST::Node, name : String)
    @runtime.gen_alloc(self, gtype, from_expr, name)
  end

  # This generates the code that stack-allocates an object of the given type.
  # This is used before calling the constructor of value types.
  def gen_alloc_alloca(gtype : GenType, name : String)
    object = gen_alloca(gtype.struct_type, name)
    gen_put_desc(object, gtype, name)
    object
  end

  # This generates more generic code for allocating a given LLVM struct type,
  # without the assumption of it being initialized as a proper runtime object.
  def gen_alloc_struct(llvm_type : LLVM::Type, name : String)
    @runtime.gen_alloc_struct(self, llvm_type, name)
  end

  # Dereference the type descriptor header of the given LLVM value,
  # loading the type descriptor of the object at runtime.
  # Prefer the above function instead when the type is statically known.
  def gen_get_desc(value : LLVM::Value)
    value_type = value.type
    raise "not a struct pointer: #{value}" \
      unless value_type.kind == LLVM::Type::Kind::Pointer

    @runtime.gen_get_desc(self, value)
  end

  def gen_put_desc(value, gtype, name = "")
    desc_p = @builder.struct_gep(@obj, value, 0, "#{name}.DESC.GEP")
    @builder.store(gtype.desc, desc_p)
    # TODO: tbaa? (from set_descriptor in libponyc/codegen/gencall.c)
  end

  def gen_local_alloca(ref, llvm_type)
    func_frame.current_locals[ref] ||= begin
      gfunc = func_frame.gfunc.not_nil!
      local_ident = func_frame.any_defn_for_local(ref)
      local_type = type_of(local_ident)
      gen_alloca(llvm_type, ref.name)
      .tap { |alloca|
        @di.declare_local(local_ident.pos, ref.name, local_type, alloca)
      }
    end
  end

  def gen_yielding_call_cont_gep(call, name)
    gfunc = func_frame.gfunc.not_nil!

    # If this is a yielding function, we store nested conts in our own cont.
    # Otherwise, we store each in its own alloca, which we create at the entry.
    if gfunc.not_nil!.needs_continuation?
      func_frame.yielding_call_conts[call]
    else
      gen_alloca(resolve_yielding_call_cont_type(call), name)
    end
  end

  def gen_yielding_call_receiver_gep(call, name)
    gfunc = func_frame.gfunc.not_nil!

    if gfunc.not_nil!.needs_continuation?
      func_frame.yielding_call_receivers[call]
    else
      gen_alloca(llvm_type_of(call.receiver), name)
    end
  end

  def gen_field_gep(name, gtype = func_frame.gtype.not_nil!)
    raise "inconsistent frames" if @frames.size > 1
    object = func_frame.receiver_value

    if object.type != @ptr
      raise "current receiver is not a pointer: #{object.inspect}"
    end

    @builder.struct_gep(
      gtype.struct_type.struct_element_types[gtype.fields_struct_index],
      @builder.struct_gep(
        gtype.struct_type,
        object,
        gtype.fields_struct_index,
        "@.FIELDS.GEP"
      ),
      gtype.field_index(name),
      "@.#{name}.GEP"
    )
  end

  def gen_field_load(name, gtype = func_frame.gtype.not_nil!)
    raise "inconsistent frames" if @frames.size > 1
    object = func_frame.receiver_value

    if object.type == gtype.fields_struct_type
      @builder.extract_value(object, gtype.field_index(name), "@.#{name}")
    else
      @builder.load(gtype.field_llvm_type(name), gen_field_gep(name, gtype), "@.#{name}")
    end
  end

  def gen_field_store(name, value)
    @builder.store(value, gen_field_gep(name))
  end

  # Calculate the number of @bitwidth-sized integers  (i.e. @isize)
  # would be needed to hold a single bit for each trait in the trait_count.
  # For example, if there are 64 traits, the trait_bitmap_size is 2,
  # but if there is a 65th trait, the trait_bitmap_size increases to 3,
  # because another integer will be added to hold that many bits.
  def trait_bitmap_size
    trait_count = @ctx.not_nil!.reach.trait_count
    ((trait_count + (@bitwidth - 1)) & ~(@bitwidth - 1)) \
      >> Math.log2(@bitwidth).to_i
  end

  def gen_send_impl(gtype, gfunc)
    # Sending a message needs a runtime-specific implementation.
    @runtime.gen_send_impl(self, gtype, gfunc)
  end

  def gen_desc_fn_impls(gtype : GenType)
    @runtime.gen_desc_fn_impls(self, gtype)
  end
end
