require "llvm"
require "random"
require "../ext/llvm" # TODO: get these merged into crystal standard library
require "compiler/crystal/config" # TODO: remove
require "./code_gen/*"

@[Link("ponyrt")]
lib LibPonyRT
  fun int_heap_index = ponyint_heap_index(size : LibC::SizeT) : UInt32
  fun int_pool_index = ponyint_pool_index(size : LibC::SizeT) : LibC::SizeT
end

class Mare::Compiler::CodeGen
  @llvm : LLVM::Context
  @mod : LLVM::Module
  @builder : LLVM::Builder
  
  class Frame
    getter func : LLVM::Function?
    getter gtype : GenType?
    getter gfunc : GenFunc?
    
    setter pony_ctx : LLVM::Value?
    property! receiver_value : LLVM::Value?
    
    getter current_locals
    
    def initialize(@g : CodeGen, @func = nil, @gtype = nil, @gfunc = nil)
      @current_locals = {} of Refer::Local => LLVM::Value
    end
    
    def func?
      @func.is_a?(LLVM::Function)
    end
    
    def func
      @func.as(LLVM::Function)
    end
    
    def pony_ctx?
      @pony_ctx.is_a?(LLVM::Value)
    end
    
    def pony_ctx
      @pony_ctx.as(LLVM::Value)
    end
    
    def refer
      @gfunc.as(GenFunc).func.refer
    end
  end
  
  class GenType
    getter type_def : Layout::Def
    getter fields : Array(Tuple(String, Layout::Ref))
    getter desc_type : LLVM::Type
    getter struct_type : LLVM::Type
    getter! desc : LLVM::Value
    getter! singleton : LLVM::Value
    
    def initialize(g : CodeGen, @type_def)
      @gfuncs = {} of String => GenFunc
      
      @fields = Array(Tuple(String, Layout::Ref)).new
      @type_def.each_function.each do |f|
        next unless f.has_tag?(:field)
        
        field_type = g.program.layout[f.infer.resolve(f.ident)]
        @fields << {f.ident.value, field_type}
      end
      
      # Generate descriptor type and struct type.
      @desc_type = g.gen_desc_type(@type_def)
      @struct_type = g.gen_struct_type(@type_def, @desc_type, fields)
    end
    
    def gen_func_decls(g : CodeGen)
      # Generate associated function declarations, some of which
      # may be referenced in the descriptor global instance below.
      @type_def.each_function.each do |f|
        next unless g.program.layout.reached_func?(f)
        
        key = f.ident.value
        key += Random::Secure.hex if f.has_tag?(:hygienic)
        @gfuncs[key] = GenFunc.new(g, self, f)
      end
    end
    
    # Generate descriptor global instance.
    def gen_desc(g : CodeGen)
      @desc = g.gen_desc(@type_def, @desc_type)
    end
    
    # Generate function implementations.
    def gen_func_impls(g : CodeGen)
      @gfuncs.each_value do |gfunc|
        next unless g.program.layout.reached_func?(gfunc.func)
        g.gen_func_impl(self, gfunc)
      end
    end
    
    # Generate other global values.
    def gen_globals(g : CodeGen)
      @singleton = g.gen_singleton(@type_def, @struct_type, @desc.not_nil!) \
        unless @type_def.has_allocation?
    end
    
    def [](name)
      @gfuncs[name]
    end
    
    def llvm_type
      @struct_type.pointer
    end
    
    def field_index(name)
      offset = 1 # TODO: not for C-like structs
      offset += 1 if @type_def.has_actor_pad?
      @fields.index { |n, _| n == name }.not_nil! + offset
    end
    
    def each_gfunc
      @gfuncs.each_value
    end
  end
  
  class GenFunc
    getter func : Program::Function
    getter llvm_name : String
    getter! llvm_func : LLVM::Function
    
    def initialize(g : CodeGen, gtype : GenType, @func, suffix : String? = nil)
      @needs_receiver = \
        gtype.type_def.has_allocation? &&
        !@func.has_tag?(:constructor) &&
        !@func.has_tag?(:constant)
      
      @llvm_name = "#{gtype.type_def.llvm_name}.#{@func.ident.value}"
      @llvm_name = "#{@llvm_name}.HYGIENIC" if func.has_tag?(:hygienic)
      @llvm_func = g.gen_func_decl(gtype, self)
    end
    
    def needs_receiver?
      @needs_receiver
    end
    
    def is_initializer?
      func.has_tag?(:field) && !func.body.nil?
    end
  end
  
  # From libponyrt/pony.h
  # Padding for actor types.
  # 
  # 56 bytes: initial header, not including the type descriptor
  # 52/104 bytes: heap
  # 48/88 bytes: gc
  # 28/0 bytes: padding to 64 bytes, ignored
  PONYRT_ACTOR_PAD_SIZE = 248
  # TODO: adjust based on intptr size to account for 32-bit platforms:
  # if INTPTR_MAX == INT64_MAX
  #  define PONYRT_ACTOR_PAD_SIZE 248
  # elif INTPTR_MAX == INT32_MAX
  #  define PONYRT_ACTOR_PAD_SIZE 160
  # endif
  
  # From libponyrt/pony.h
  PONYRT_TRACE_MUTABLE = 0
  PONYRT_TRACE_IMMUTABLE = 1
  PONYRT_TRACE_OPAQUE = 2
  
  # From libponyrt/mem/pool.h
  PONYRT_POOL_MIN_BITS = 5
  PONYRT_POOL_MAX_BITS = 20
  PONYRT_POOL_ALIGN_BITS = 10
  
  # From libponyrt/mem/heap.h
  PONYRT_HEAP_MINBITS = 5
  PONYRT_HEAP_MAXBITS = (PONYRT_POOL_ALIGN_BITS - 1)
  PONYRT_HEAP_SIZECLASSES = (PONYRT_HEAP_MAXBITS - PONYRT_HEAP_MINBITS + 1)
  PONYRT_HEAP_MIN = (1_u64 << PONYRT_HEAP_MINBITS)
  PONYRT_HEAP_MAX = (1_u64 << PONYRT_HEAP_MAXBITS)
  
  PONYRT_BC_PATH = "/home/jemc/1/code/gitx/ponyc/build/release/libponyrt.bc"
  
  getter! program : Program
  
  def initialize
    LLVM.init_x86
    @target_triple = Crystal::Config.default_target_triple
    @target = LLVM::Target.from_triple(@target_triple)
    @target_machine = @target.create_target_machine(@target_triple).as(LLVM::TargetMachine)
    @llvm = LLVM::Context.new
    @mod = @llvm.new_module("minimal")
    @builder = @llvm.new_builder
    
    @default_linkage = LLVM::Linkage::External
    
    @void    = @llvm.void.as(LLVM::Type)
    @ptr     = @llvm.int8.pointer.as(LLVM::Type)
    @pptr    = @llvm.int8.pointer.pointer.as(LLVM::Type)
    @i1      = @llvm.int1.as(LLVM::Type)
    @i8      = @llvm.int8.as(LLVM::Type)
    @i32     = @llvm.int32.as(LLVM::Type)
    @i32_ptr = @llvm.int32.pointer.as(LLVM::Type)
    @i32_0   = @llvm.int32.const_int(0).as(LLVM::Value)
    @i64     = @llvm.int64.as(LLVM::Type)
    @intptr  = @llvm.intptr(@target_machine.data_layout).as(LLVM::Type)
    
    @frames = [] of Frame
    @string_globals = {} of String => LLVM::Value
    @gtypes = {} of String => GenType
    
    # ponyrt_bc = LLVM::MemoryBuffer.from_file(PONYRT_BC_PATH)
    # @ponyrt = @llvm.parse_bitcode(ponyrt_bc).as(LLVM::Module)
    
    # Pony runtime types.
    @desc = @llvm.opaque_struct("_.DESC").as(LLVM::Type)
    @desc_ptr = @desc.pointer.as(LLVM::Type)
    @obj = @llvm.opaque_struct("_.OBJECT").as(LLVM::Type)
    @obj_ptr = @obj.pointer.as(LLVM::Type)
    @actor_pad = @i8.array(PONYRT_ACTOR_PAD_SIZE).as(LLVM::Type)
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
    
    # Pony runtime function declarations.
    gen_runtime_decls
  end
  
  def frame
    @frames.last
  end
  
  def func_frame
    @frames.reverse_each.find { |f| f.func? }.not_nil!
  end
  
  def type_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    in_gfunc ||= func_frame.gfunc.not_nil!
    inferred = in_gfunc.func.infer.resolve(expr)
    program.layout[inferred]
  end
  
  def llvm_type_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    llvm_type_of(type_of(expr, in_gfunc))
  end
  
  def llvm_type_of(ref : Layout::Ref)
    case ref.llvm_use_type
    when :i8, :u8 then @i8
    when :i32, :u32 then @i32
    when :i64, :u64 then @i64
    when :ptr then @ptr
    when :struct_ptr then
      @gtypes[program.layout[ref.single!].llvm_name].llvm_type
    else raise NotImplementedError.new(ref.llvm_use_type)
    end
  end
  
  def llvm_mem_type_of(ref : Layout::Ref)
    case ref.llvm_mem_type
    when :i8, :u8 then @i8
    when :i32, :u32 then @i32
    when :i64, :u64 then @i64
    when :ptr then @ptr
    when :struct_ptr then
      @gtypes[program.layout[ref.single!].llvm_name].llvm_type
    else raise NotImplementedError.new(ref.llvm_mem_type)
    end
  end
  
  def gtype_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    llvm_name = program.layout[type_of(expr, in_gfunc).single!].llvm_name
    @gtypes[llvm_name]
  end
  
  def pony_ctx
    return func_frame.pony_ctx if func_frame.pony_ctx?
    func_frame.pony_ctx = @builder.call(@mod.functions["pony_ctx"], "PONY_CTX")
  end
  
  def self.run(ctx)
    new.run(ctx)
  end
  
  def run(ctx : Context)
    @program = ctx.program
    ctx.program.code_gen = self
    
    # Generate all type descriptors and function declarations.
    ctx.program.layout.each_type_def.each do |type_def|
      @gtypes[type_def.llvm_name] = GenType.new(self, type_def)
    end
    
    # Generate all function declarations.
    @gtypes.each_value(&.gen_func_decls(self))
    
    # Generate all global descriptor instances.
    @gtypes.each_value(&.gen_desc(self))
    
    # Generate all global values associated with this type.
    @gtypes.each_value(&.gen_globals(self))
    
    # Generate all function implementations.
    @gtypes.each_value(&.gen_func_impls(self))
    
    # Generate the internal main function.
    gen_main
    
    # Generate the wrapper main function for the JIT.
    gen_wrapper
    
    # Run LLVM sanity checks on the generated module.
    @mod.verify
    
    # # Link the pony runtime bitcode into the generated module.
    # LibLLVM.link_modules(@mod.to_unsafe, @ponyrt.to_unsafe)
  end
  
  def jit!
    # Run the function!
    LLVM::JITCompiler.new @mod do |jit|
      jit.run_function(@mod.functions["__mare_jit"], @llvm).to_i
    end
  end
  
  def gen_wrapper
    # Declare the wrapper function for the JIT.
    wrapper = @mod.functions.add("__mare_jit", ([] of LLVM::Type), @i32)
    wrapper.linkage = LLVM::Linkage::External
    
    # Create a basic block to hold the implementation of the main function.
    bb = wrapper.basic_blocks.append("entry")
    @builder.position_at_end bb
    
    # Construct the following arguments to pass to the main function:
    # i32 argc = 0, i8** argv = ["marejit", NULL], i8** envp = [NULL]
    argc = @i32.const_int(1)
    argv = @builder.alloca(@i8.pointer.array(2), "argv")
    envp = @builder.alloca(@i8.pointer.array(1), "envp")
    argv_0 = @builder.inbounds_gep(argv, @i32_0, @i32_0, "argv_0")
    argv_1 = @builder.inbounds_gep(argv, @i32_0, @i32.const_int(1), "argv_1")
    envp_0 = @builder.inbounds_gep(envp, @i32_0, @i32_0, "envp_0")
    @builder.store(gen_string("marejit"), argv_0)
    @builder.store(@ptr.null, argv_1)
    @builder.store(@ptr.null, envp_0)
    
    # Call the main function with the constructed arguments.
    res = @builder.call(@mod.functions["main"], [argc, argv_0, envp_0], "res")
    @builder.ret(res)
  end
  
  def gen_main
    # Declare the main function.
    main = @mod.functions.add("main", [@i32, @pptr, @pptr], @i32)
    main.linkage = LLVM::Linkage::External
    
    gen_func_start(main)
    
    argc = main.params[0].tap &.name=("argc")
    argv = main.params[1].tap &.name=("argv")
    envp = main.params[2].tap &.name=("envp")
    
    # Call pony_init, letting it optionally consume some of the CLI args,
    # giving us a new value for argc and a mutated argv array.
    argc = @builder.call(@mod.functions["pony_init"], [@i32.const_int(1), argv], "argc")
    
    # Get the current pony_ctx and hold on to it.
    pony_ctx = @builder.call(@mod.functions["pony_ctx"], "ctx")
    func_frame.pony_ctx = pony_ctx
    
    # Create the main actor and become it.
    main_actor = @builder.call(@mod.functions["pony_create"],
      [pony_ctx, gen_get_desc("Main")], "main_actor")
    @builder.call(@mod.functions["pony_become"], [pony_ctx, main_actor])
    
    # Create the Env from argc, argv, and envp.
    env = gen_alloc(@gtypes["Env"], "env")
    # TODO: @builder.call(env__create_fn,
    #   [argc, @builder.bit_cast(argv, @ptr), @builder.bitcast(envp, @ptr)])
    
    # TODO: Run primitive initialisers using the main actor's heap.
    
    # Create a one-off message type and allocate a message.
    msg_type = @llvm.struct([@i32, @i32, @ptr, env.type])
    vtable_index = 0 # TODO: get actual vtable of Main.new
    msg_size = @target_machine.data_layout.abi_size(msg_type)
    pool_index = LibPonyRT.int_pool_index(msg_size)
    msg_opaque = @builder.call(@mod.functions["pony_alloc_msg"],
      [@i32.const_int(pool_index), @i32.const_int(vtable_index)], "msg_opaque")
    msg = @builder.bit_cast(msg_opaque, msg_type.pointer, "msg")
    
    # Put the env into the message.
    msg_env_p = @builder.struct_gep(msg, 3, "msg_env_p")
    @builder.store(env, msg_env_p)
    
    # Trace the message.
    @builder.call(@mod.functions["pony_gc_send"], [func_frame.pony_ctx])
    @builder.call(@mod.functions["pony_traceknown"], [
      func_frame.pony_ctx,
      @builder.bit_cast(env, @obj_ptr, "env_as_obj"),
      @llvm.const_bit_cast(@gtypes["Env"].desc, @desc_ptr),
      @i32.const_int(PONYRT_TRACE_IMMUTABLE),
    ])
    @builder.call(@mod.functions["pony_send_done"], [func_frame.pony_ctx])
    
    # Send the message.
    @builder.call(@mod.functions["pony_sendv_single"], [
      func_frame.pony_ctx,
      main_actor,
      msg_opaque,
      msg_opaque,
      @i1.const_int(1)
    ])
    
    # Start the runtime.
    start_success = @builder.call(@mod.functions["pony_start"], [
      @i1.const_int(0),
      @i32_ptr.null,
      @ptr.null, # TODO: pony_language_features_init_t*
    ], "start_success")
    
    # Branch based on the value of `start_success`.
    start_fail_block = gen_block("start_fail")
    post_block = gen_block("post")
    @builder.cond(start_success, post_block, start_fail_block)
    
    # On failure, just write a failure message then continue to the post_block.
    @builder.position_at_end(start_fail_block)
    @builder.call(@mod.functions["puts"], [
      gen_string("Error: couldn't start the runtime!")
    ])
    @builder.br(post_block)
    
    # On success (or after running the failure block), do the following:
    @builder.position_at_end(post_block)
    
    # TODO: Run primitive finalizers.
    
    # Become nothing (stop being the main actor).
    @builder.call(@mod.functions["pony_become"], [
      func_frame.pony_ctx,
      @obj_ptr.null,
    ])
    
    # Get the program's chosen exit code (or 0 by default), but override
    # it with -1 if we failed to start the runtime.
    exitcode = @builder.call(@mod.functions["pony_get_exitcode"], "exitcode")
    ret = @builder.select(start_success, exitcode, @i32.const_int(-1), "ret")
    @builder.ret(ret)
    
    gen_func_end
    
    main
  end
  
  def gen_func_start(llvm_func, gtype : GenType? = nil, gfunc : GenFunc? = nil)
    @frames << Frame.new(self, llvm_func, gtype, gfunc)
    
    # Create an entry block and start building from there.
    @builder.position_at_end(gen_block("entry"))
  end
  
  def gen_func_end
    @frames.pop
  end
  
  def gen_block(name)
    frame.func.basic_blocks.append(name)
  end
  
  def ffi_type_for(ident)
    case ident.value
    when "I32"     then @i32
    when "CString" then @ptr
    when "None"    then @void
    else raise NotImplementedError.new(ident.value)
    end
  end
  
  def gen_get_desc(name)
    @llvm.const_bit_cast(@gtypes[name].desc, @desc_ptr)
  end
  
  def gen_func_decl(gtype, gfunc)
    # TODO: these should probably not use the ffi_type_for each type?
    param_types = [] of LLVM::Type
    gfunc.func.params.try do |params|
      params.terms.map do |param|
        param_types << llvm_type_of(param, gfunc)
      end
    end
    
    # Add implicit receiver parameter if needed.
    param_types.unshift(gtype.llvm_type) if gfunc.needs_receiver?
    
    ret_type = llvm_type_of(gfunc.func.ident, gfunc)
    
    @mod.functions.add(gfunc.llvm_name, param_types, ret_type)
  end
  
  def gen_func_impl(gtype, gfunc)
    return gen_ffi_body(gtype, gfunc) if gtype.type_def.is_ffi?
    
    # Fields with no initializer body can be skipped.
    return if gfunc.func.has_tag?(:field) && gfunc.func.body.nil?
    
    gen_func_start(gfunc.llvm_func, gtype, gfunc)
    
    # Set a receiver value (the value of the self in this function).
    func_frame.receiver_value =
      if gfunc.func.has_tag?(:constructor)
        gen_alloc(gtype)
      elsif gfunc.needs_receiver?
        gfunc.llvm_func.params[0]
      elsif gtype.singleton?
        gtype.singleton
      end
    
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
        init_value = @builder.call(init_func.llvm_func, call_args)
        gen_field_store(name, init_value)
      end
    end
    
    # Now generate code for the expressions in the function body.
    last_value = nil
    gfunc.func.body.not_nil!.terms.each do |expr|
      last_value = gen_expr(expr, gfunc.func.has_tag?(:constant))
    end
    @builder.ret(last_value.not_nil!)
    
    gen_func_end
  end
  
  def gen_ffi_decl(gfunc)
    params = gfunc.func.params.not_nil!.terms.map do |param|
      ffi_type_for(param.as(AST::Identifier))
    end
    ret = ffi_type_for(gfunc.func.ret.not_nil!)
    
    # Prevent double-declaring for common FFI functions already known to us.
    llvm_ffi_func = @mod.functions[gfunc.func.ident.value]?
    if llvm_ffi_func
      # TODO: verify that parameter types and return type are compatible
      return @mod.functions[gfunc.func.ident.value]
    end
    
    @mod.functions.add(gfunc.func.ident.value, params, ret)
  end
  
  def gen_ffi_body(gtype, gfunc)
    llvm_ffi_func = gen_ffi_decl(gfunc)
    
    gen_func_start(gfunc.llvm_func, gtype, gfunc)
    
    param_count = gfunc.llvm_func.params.size
    args = param_count.times.map { |i| gfunc.llvm_func.params[i] }.to_a
    
    value = @builder.call llvm_ffi_func, args
    value = gen_none if llvm_ffi_func.return_type == @void
    
    @builder.ret(value)
    
    gen_func_end
  end
  
  def gen_dot(relate)
    rhs = relate.rhs
    
    case rhs
    when AST::Identifier
      member = rhs.value
      args = [] of LLVM::Value
    when AST::Qualify
      member = rhs.term.as(AST::Identifier).value
      args = rhs.group.terms.map { |expr| gen_expr(expr).as(LLVM::Value) }
    else raise NotImplementedError.new(rhs)
    end
    
    relate.lhs.as(AST::Identifier) # assert that lhs is an identifier
    lhs_gtype = gtype_of(relate.lhs)
    gfunc = lhs_gtype[member]
    
    if gfunc.needs_receiver?
      receiver = gen_expr(relate.lhs)
      args.unshift(receiver)
    end
    
    @builder.call(gfunc.llvm_func, args)
  end
  
  def gen_eq(relate)
    value = gen_expr(relate.rhs).as(LLVM::Value)
    
    ref = func_frame.refer[relate.lhs]
    if ref.is_a?(Refer::Local)
      raise "local already declared: #{ref.inspect}" \
        if func_frame.current_locals[ref]?
      
      value.name = ref.name
      func_frame.current_locals[ref] = value
    elsif ref.is_a?(Refer::Field)
      old_value = gen_field_load(ref.name)
      gen_field_store(ref.name, value)
      old_value
    else raise NotImplementedError.new(relate.inspect)
    end
  end
  
  def gen_expr(expr, const_only = false) : LLVM::Value
    case expr
    when AST::Identifier
      ref = func_frame.refer[expr]
      if ref.is_a?(Refer::Local) && ref.param_idx
        raise "#{ref.inspect} isn't a constant value" if const_only
        param_idx = ref.param_idx.not_nil!
        param_idx -= 1 unless func_frame.gfunc.not_nil!.needs_receiver?
        frame.func.params[param_idx]
      elsif ref.is_a?(Refer::Local)
        raise "#{ref.inspect} isn't a constant value" if const_only
        func_frame.current_locals[ref]
      elsif ref.is_a?(Refer::Const)
        gtype = gtype_of(expr)
        case gtype
        when @gtypes["True"]? then gen_bool(true)
        when @gtypes["False"]? then gen_bool(false)
        else gtype.singleton
        end
      elsif ref.is_a?(Refer::Self)
        raise "#{ref.inspect} isn't a constant value" if const_only
        func_frame.receiver_value
      else
        raise NotImplementedError.new(ref)
      end
    when AST::Field
      gen_field_load(expr.value)
    when AST::LiteralInteger
      gen_integer(expr)
    when AST::LiteralString
      gen_string(expr)
    when AST::Relate
      raise "#{expr.inspect} isn't a constant value" if const_only
      case expr.op.as(AST::Operator).value
      when "." then gen_dot(expr)
      when "=" then gen_eq(expr)
      else raise NotImplementedError.new(expr.inspect)
      end
    when AST::Group
      raise "#{expr.inspect} isn't a constant value" if const_only
      case expr.style
      when "(", ":" then gen_sequence(expr)
      else raise NotImplementedError.new(expr.inspect)
      end
    when AST::Choice
      raise "#{expr.inspect} isn't a constant value" if const_only
      gen_choice(expr)
    else
      raise NotImplementedError.new(expr.inspect)
    end
  end
  
  def gen_none
    @gtypes["None"].singleton
  end
  
  def gen_bool(bool)
    @i1.const_int(bool ? 1 : 0)
  end
  
  def gen_integer(expr : AST::LiteralInteger)
    type_ref = type_of(expr)
    case type_ref.llvm_use_type
    when :i8 then @i8.const_int(expr.value.to_i8)
    when :i32 then @i32.const_int(expr.value.to_i32)
    when :i64 then @i64.const_int(expr.value.to_i64)
    when :f32 then raise NotImplementedError.new("float literals")
    when :f64 then raise NotImplementedError.new("float literals")
    else raise "invalid numeric literal type: #{type_ref}"
    end
  end
  
  def gen_string(expr_or_value)
    @llvm.const_inbounds_gep(gen_string_global(expr_or_value), [@i32_0, @i32_0])
  end
  
  def gen_string_global(expr : AST::LiteralString) : LLVM::Value
    gen_string_global(expr.value)
  end
  
  def gen_string_global(value : String) : LLVM::Value
    @string_globals.fetch value do
      const = @llvm.const_string(value)
      global = @mod.globals.add(const.type, "")
      global.linkage = LLVM::Linkage::External
      global.initializer = const
      global.global_constant = true
      global.unnamed_addr = true
      
      @string_globals[value] = global
    end
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
  
  def gen_choice(expr : AST::Choice)
    # TODO: Support more than a simple if/else choice.
    raise NotImplementedError.new(expr.list.size) if expr.list.size != 2
    
    if_clause = expr.list.first
    else_clause = expr.list.last
    
    cond_value = gen_expr(if_clause[0])
    
    bb_body1 = gen_block("body1choice")
    bb_body2 = gen_block("body2choice")
    bb_post  = gen_block("postchoice")
    
    # TODO: Use infer resolution for static True/False finding where possible.
    @builder.cond(cond_value, bb_body1, bb_body2)
    
    @builder.position_at_end(bb_body1)
    value1 = gen_expr(if_clause[1])
    @builder.br(bb_post)
    
    @builder.position_at_end(bb_body2)
    value2 = gen_expr(else_clause[1])
    @builder.br(bb_post)
    
    @builder.position_at_end(bb_post)
    phi_type = value1.type # TODO: inferred union of all branch types
    @builder.phi(phi_type, [bb_body1, bb_body2], [value1, value2], "phichoice")
  end
  
  def gen_desc_type(type_def : Layout::Def) : LLVM::Type
    @llvm.struct [
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
      @pptr,                          # 14: TODO: traits
      @pptr,                          # 15: TODO: fields
      @pptr,                          # 16: TODO: vtable
    ], "#{type_def.llvm_name}.DESC"
  end
  
  def gen_desc(type_def, desc_type)
    global = @mod.globals.add(desc_type, "#{type_def.llvm_name}.DESC")
    global.linkage = LLVM::Linkage::LinkerPrivate
    global.global_constant = true
    global
    
    case type_def.llvm_name
    when "Main"
      dispatch_fn = @mod.functions.add("#{type_def.llvm_name}.DISPATCH", @dispatch_fn) do |fn|
        fn.unnamed_addr = true
        fn.call_convention = LLVM::CallConvention::C
        fn.linkage = LLVM::Linkage::External
        
        gen_func_start(fn)
        
        @builder.call(@mod.functions["Main.new"])
        
        @builder.ret
        
        gen_func_end
      end
      
      traits = @pptr.null # TODO
      fields = @pptr.null # TODO
      vtable = @pptr.null # TODO
    else
      dispatch_fn = @dispatch_fn_ptr.null # TODO
      traits = @pptr.null # TODO
      fields = @pptr.null # TODO
      vtable = @pptr.null # TODO
    end
    
    global.initializer = desc_type.const_struct [
      @i32.const_int(type_def.desc_id),      # 0: id
      @i32.const_int(type_def.abi_size),     # 1: size
      @i32_0,                                # 2: TODO: field_count (tuples only)
      @i32.const_int(type_def.field_offset), # 3: field_offset
      @obj_ptr.null,                         # 4: instance
      @trace_fn_ptr.null,                    # 5: trace fn TODO: @#{llvm_name}.TRACE
      @trace_fn_ptr.null,                    # 6: serialise trace fn TODO: @#{llvm_name}.TRACE
      @serialise_fn_ptr.null,                # 7: serialise fn TODO: @#{llvm_name}.SERIALISE
      @deserialise_fn_ptr.null,              # 8: deserialise fn TODO: @#{llvm_name}.DESERIALISE
      @custom_serialise_space_fn_ptr.null,   # 9: custom serialise space fn
      @custom_deserialise_fn_ptr.null,       # 10: custom deserialise fn
      dispatch_fn.to_value,                  # 11: dispatch fn
      @final_fn_ptr.null,                    # 12: final fn
      @i32.const_int(-1),                    # 13: event notify TODO
      traits,                                # 14: TODO: traits
      fields,                                # 15: TODO: fields
      vtable,                                # 16: TODO: vtable
    ]
    
    global
  end
  
  def gen_struct_type(type_def, desc_type, fields)
    elements = [] of LLVM::Type
    elements << desc_type.pointer if type_def.has_desc?
    elements << @actor_pad if type_def.has_actor_pad?
    
    fields.each { |name, t| elements << llvm_mem_type_of(t) }
    
    @llvm.struct(elements, type_def.llvm_name)
  end
  
  def gen_singleton(type_def, struct_type, desc)
    raise "can't generate stateful singleton" if type_def.has_allocation?
    
    global = @mod.globals.add(struct_type, type_def.llvm_name)
    global.linkage = LLVM::Linkage::LinkerPrivate
    global.global_constant = true
    
    global.initializer = struct_type.const_struct([desc])
    
    global
  end
  
  def gen_alloc(gtype, name = "@")
    raise NotImplementedError.new(gtype.type_def) \
      unless gtype.type_def.has_allocation?
    
    size = gtype.type_def.abi_size
    size = 1 if size == 0
    args = [pony_ctx]
    
    value =
      if size <= PONYRT_HEAP_MAX
        index = LibPonyRT.int_heap_index(size).to_i32
        args << @i32.const_int(index)
        # TODO: handle case where final_fn is present (pony_alloc_small_final)
        @builder.call(@mod.functions["pony_alloc_small"], args, "#{name}.MEM")
      else
        args << @intptr.const_int(size)
        # TODO: handle case where final_fn is present (pony_alloc_large_final)
        @builder.call(@mod.functions["pony_alloc_large"], args, "#{name}.MEM")
      end
    
    value = @builder.bit_cast(value, gtype.llvm_type, name)
    gen_put_desc(value, gtype, name)
    
    value
  end
  
  def gen_put_desc(value, gtype, name = "")
    raise NotImplementedError.new(gtype) unless gtype.type_def.has_desc?
    
    desc_p = @builder.struct_gep(value, 0, "#{name}.DESC")
    @builder.store(gtype.desc, desc_p)
    # TODO: tbaa? (from set_descriptor in libponyc/codegen/gencall.c)
  end
  
  def gen_field_load(name)
    gtype = func_frame.gtype.not_nil!
    object = func_frame.receiver_value
    gep = @builder.struct_gep(object, gtype.field_index(name), "@.#{name}")
    @builder.load(gep)
  end
  
  def gen_field_store(name, value)
    gtype = func_frame.gtype.not_nil!
    object = func_frame.receiver_value
    gep = @builder.struct_gep(object, gtype.field_index(name), "@.#{name}")
    @builder.store(value, gep)
  end
end
