require "llvm"
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
    getter program : Program
    getter func : LLVM::Function?
    getter program_func : Program::Function?
    setter pony_ctx : LLVM::Value?
    getter current_locals
    
    def initialize(@program : Program, @func = nil, @program_func = nil)
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
      @program_func.as(Program::Function).refer
    end
    
    def type_of(expr)
      inferred = @program_func.as(Program::Function).infer.resolve(expr)
      @program.layout[inferred]
    end
  end
  
  class GenType
    getter type_def : Layout::Def
    getter desc_type : LLVM::Type
    getter desc : LLVM::Value
    getter structure : LLVM::Type
    
    def initialize(ctx : Context, g : CodeGen, program_type)
      @type_def = ctx.program.layout[program_type]
      
      @desc_type = g.gen_desc_type(@type_def)
      @desc = g.gen_desc(ctx, @type_def, @desc_type)
      @structure = g.gen_structure(@type_def, @desc_type)
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
    @desc = @llvm.opaque_struct("__Desc").as(LLVM::Type)
    @desc_ptr = @desc.pointer.as(LLVM::Type)
    @obj = @llvm.opaque_struct("__object").as(LLVM::Type)
    @obj_ptr = @obj.pointer.as(LLVM::Type)
    @actor_pad = @i8.array(PONYRT_ACTOR_PAD_SIZE).as(LLVM::Type)
    @msg = @llvm.struct([@i32, @i32], "__message").as(LLVM::Type)
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
  
  def type_of(expr)
    func_frame.type_of(expr)
  end
  
  def self.run(ctx)
    new.run(ctx)
  end
  
  def run(ctx : Context)
    ctx.program.code_gen = self
    
    # CodeGen for all function declarations.
    ctx.program.types.each do |t|
      case t.kind
      when Program::Type::Kind::Actor,
           Program::Type::Kind::Class,
           Program::Type::Kind::Primitive,
           Program::Type::Kind::Numeric
        t.functions.each { |f| gen_fun_decl(t, f) }
      when Program::Type::Kind::FFI
        t.functions.each { |f| gen_ffi_decl(f) }
      else raise NotImplementedError.new(t.kind)
      end
    end
    
    # CodeGen for all types.
    # TODO: dynamically gather these from ctx.program.
    type_defs = {
      "Main" => ctx.program.find_type!("Main"),
      "Env" => ctx.program.find_type!("Env"),
    }
    type_defs.each do |name, type_def|
      @gtypes[name] = GenType.new(ctx, self, type_def)
    end
    
    # CodeGen for all function bodies.
    ctx.program.types.each do |t|
      t.functions.each { |f| gen_fun_body(ctx, t, f) if f.body }
    end
    
    # Generate the internal main function.
    gen_main(ctx)
    
    # Generate the wrapper main function.
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
  
  def gen_main(ctx : Context)
    # Declare the main function.
    main = @mod.functions.add("main", [@i32, @pptr, @pptr], @i32)
    main.linkage = LLVM::Linkage::External
    
    gen_func_start(ctx, main)
    
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
  
  def gen_func_start(ctx, func, program_func : Program::Function? = nil)
    @frames << Frame.new(ctx.program, func, program_func)
    
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
  
  def gen_ffi_decl(f)
    params = f.params.not_nil!.terms.map do |param|
      ffi_type_for(param.as(AST::Identifier))
    end
    ret = ffi_type_for(f.ret.not_nil!)
    
    @mod.functions.add(f.ident.value, params, ret)
  end
  
  def gen_fun_decl(t, f)
    # TODO: these should probably not use the ffi_type_for each type?
    params = [] of LLVM::Type
    f.params.try do |param_idents|
      param_idents.terms.map do |param|
        param_type_ident =
          case param
          when AST::Identifier then param
          when AST::Group then param.terms[1].as(AST::Identifier)
          else raise NotImplementedError.new(param)
          end
        
        params << ffi_type_for(param_type_ident)
      end
    end
    ret = f.ret.try { |ret_ident| ffi_type_for(ret_ident) } || @void
    
    ident = "#{t.ident.value}.#{f.ident.value}"
    @mod.functions.add(ident, params, ret)
  end
  
  def gen_fun_body(ctx, t, f)
    func = @mod.functions["#{t.ident.value}.#{f.ident.value}"]
    
    gen_func_start(ctx, func, f)
    
    last_value = nil
    f.body.not_nil!.terms.each { |expr| last_value = gen_expr(ctx, expr) }
    
    if f.ret
      @builder.ret(last_value.not_nil!)
    else
      @builder.ret
    end
    
    gen_func_end
  end
  
  def gen_dot(ctx, relate)
    receiver = relate.lhs.as(AST::Identifier).value
    rhs = relate.rhs
    
    case rhs
    when AST::Identifier
      member = rhs.value
      args = [] of LLVM::Value
    when AST::Qualify
      member = rhs.term.as(AST::Identifier).value
      args = rhs.group.terms.map { |expr| gen_expr(ctx, expr).as(LLVM::Value) }
    else raise NotImplementedError.new(rhs)
    end
    
    receiver_type = ctx.program.find_type!(receiver)
    
    case receiver_type.kind
    when Program::Type::Kind::FFI
      ffi = @mod.functions[member]
      value = @builder.call(ffi, args)
      value = gen_none if ffi.return_type == @void
      value
    when Program::Type::Kind::Primitive, Program::Type::Kind::Numeric
      @builder.call(@mod.functions["#{receiver}.#{member}"], args)
    else raise NotImplementedError.new(receiver_type)
    end
  end
  
  def gen_eq(ctx, relate)
    ref = func_frame.refer[relate.lhs]
    if ref.is_a?(Refer::Local)
      rhs = gen_expr(ctx, relate.rhs).as(LLVM::Value)
      
      raise "local already declared: #{ref.inspect}" \
        if func_frame.current_locals[ref]?
      
      rhs.name = ref.name
      func_frame.current_locals[ref] = rhs
    else raise NotImplementedError.new(relate.inspect)
    end
  end
  
  def gen_expr(ctx, expr) : LLVM::Value
    case expr
    when AST::Identifier
      ref = func_frame.refer[expr]
      if ref.is_a?(Refer::Local) && ref.param_idx
        param_idx = ref.param_idx.not_nil! - 1 # TODO: only for primitive calls
        frame.func.params[param_idx]
      elsif ref.is_a?(Refer::Local)
        func_frame.current_locals[ref]
      elsif ref.is_a?(Refer::Const)
        case ref.defn.ident.value # TODO: deal with namespacing properly
        when "True"  then gen_bool(true)
        when "False" then gen_bool(false)
        when "None"  then gen_none
        else raise NotImplementedError.new(ref.defn.ident.value)
        end
      else
        raise NotImplementedError.new(ref)
      end
    when AST::LiteralInteger
      gen_integer(expr)
    when AST::LiteralString
      gen_string(expr)
    when AST::Relate
      case expr.op.as(AST::Operator).value
      when "." then gen_dot(ctx, expr)
      when "=" then gen_eq(ctx, expr)
      else raise NotImplementedError.new(expr.inspect)
      end
    when AST::Group
      case expr.style
      when "(" then gen_sequence(ctx, expr)
      else raise NotImplementedError.new(expr.inspect)
      end
    when AST::Choice
      gen_choice(ctx, expr)
    else
      raise NotImplementedError.new(expr.inspect)
    end
  end
  
  def gen_none
    @ptr.null # TODO: the real value
  end
  
  def gen_bool(bool)
    @i1.const_int(bool ? 1 : 0)
  end
  
  def gen_integer(expr : AST::LiteralInteger)
    type_ref = func_frame.type_of(expr)
    case type_ref.llvm_use_type
    when :i8 then @i8.const_int(expr.value.to_i8)
    when :u8 then @i8.const_int(expr.value.to_u8)
    when :u32 then @i32.const_int(expr.value.to_u32)
    when :i32 then @i32.const_int(expr.value.to_i32)
    when :u64 then @i64.const_int(expr.value.to_u64)
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
  
  def gen_sequence(ctx, expr : AST::Group)
    # TODO: Use None as a value when sequence group size is zero.
    raise NotImplementedError.new(expr.terms.size) if expr.terms.size == 0
    
    # TODO: Push a scope frame?
    
    final : LLVM::Value? = nil
    expr.terms.each { |term| final = gen_expr(ctx, term) }
    final.not_nil!
    
    # TODO: Pop the scope frame?
  end
  
  def gen_choice(ctx, expr : AST::Choice)
    # TODO: Support more than a simple if/else choice.
    raise NotImplementedError.new(expr.list.size) if expr.list.size != 2
    
    if_clause = expr.list.first
    else_clause = expr.list.last
    
    cond_value = gen_expr(ctx, if_clause[0])
    
    bb_body1 = gen_block("body1choice")
    bb_body2 = gen_block("body2choice")
    bb_post  = gen_block("postchoice")
    
    # TODO: Use infer resolution for static True/False finding where possible.
    @builder.cond(cond_value, bb_body1, bb_body2)
    
    @builder.position_at_end(bb_body1)
    value1 = gen_expr(ctx, if_clause[1])
    @builder.br(bb_post)
    
    @builder.position_at_end(bb_body2)
    value2 = gen_expr(ctx, else_clause[1])
    @builder.br(bb_post)
    
    @builder.position_at_end(bb_post)
    phi_type = @ptr # TODO: the real type
    @builder.phi(@ptr, [bb_body1, bb_body2], [value1, value2], "phichoice")
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
    ], type_def.llvm_desc_name
  end
  
  def gen_desc(ctx, type_def, desc_type)
    global = @mod.globals.add(desc_type, type_def.llvm_desc_name)
    global.linkage = LLVM::Linkage::LinkerPrivate
    global.global_constant = true
    global
    
    case type_def.llvm_name
    when "Main"
      dispatch_fn = @mod.functions.add("#{type_def.llvm_name}_Dispatch", @dispatch_fn) do |fn|
        fn.unnamed_addr = true
        fn.call_convention = LLVM::CallConvention::C
        fn.linkage = LLVM::Linkage::External
        
        gen_func_start(ctx, fn)
        
        @builder.call(@mod.functions["Main.new"])
        
        @builder.ret
        
        gen_func_end
      end
      
      traits = @pptr.null # TODO
      fields = @pptr.null # TODO
      vtable = @pptr.null # TODO
    when "Env"
      dispatch_fn = @dispatch_fn_ptr.null
      traits = @pptr.null # [1 x i64]* @Env_Traits
      fields = @pptr.null # [0 x { i32, %__Desc* }]* null
      vtable = @pptr.null # TODO: ~~v
      # [9 x i8*] [
      #   i8* bitcast (%Array_String_val* (%Env*, i8*, i64)* @Env_tag__strings_from_pointers_oZo to i8*),
      #   i8* bitcast (i64 (%Env*, i8*)* @Env_tag__count_strings_oZ to i8*),
      #   i8* bitcast (i64 (%Env*, i8*)* @Env_tag__count_strings_oZ to i8*),
      #   i8* bitcast (void (%Env*, i32, i8*, i8*)* @Env_ref__create_Iooo to i8*),
      #   i8* bitcast (%Array_String_val* (%Env*, i8*, i64)* @Env_tag__strings_from_pointers_oZo to i8*),
      #   i8* bitcast (i64 (%Env*, i8*)* @Env_tag__count_strings_oZ to i8*),
      #   i8* bitcast (i64 (%Env*, i8*)* @Env_tag__count_strings_oZ to i8*),
      #   i8* bitcast (%Array_String_val* (%Env*, i8*, i64)* @Env_tag__strings_from_pointers_oZo to i8*),
      #   i8* bitcast (%Array_String_val* (%Env*, i8*, i64)* @Env_tag__strings_from_pointers_oZo to i8*)
      # ] }
    else
      raise NotImplementedError.new(type_def.llvm_name)
    end
    
    global.initializer = desc_type.const_struct [
      @i32.const_int(type_def.desc_id),      # 0: id
      @i32.const_int(type_def.abi_size),     # 1: size
      @i32_0,                                # 2: TODO: field_count (tuples only)
      @i32.const_int(type_def.field_offset), # 3: field_offset
      @obj_ptr.null,                         # 4: instance
      @trace_fn_ptr.null,                    # 5: trace fn TODO: @#{llvm_name}_Trace
      @trace_fn_ptr.null,                    # 6: serialise trace fn TODO: @#{llvm_name}_Trace
      @serialise_fn_ptr.null,                # 7: serialise fn TODO: @#{llvm_name}_Serialise
      @deserialise_fn_ptr.null,              # 8: deserialise fn TODO: @#{llvm_name}_Deserialise
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
  
  def gen_structure(type_def, desc_type)
    elements = [] of LLVM::Type
    elements << desc_type.pointer if type_def.has_desc?
    elements << @actor_pad if type_def.has_actor_pad?
    # TODO: fields
    
    @llvm.struct(elements, type_def.llvm_name)
  end
  
  def gen_alloc(gtype, name = "")
    raise NotImplementedError.new(gtype.type_def) \
      unless gtype.type_def.has_allocation?
    
    size = gtype.type_def.abi_size
    size = 1 if size == 0
    args = [func_frame.pony_ctx]
    
    value =
      if size <= PONYRT_HEAP_MAX
        index = LibPonyRT.int_heap_index(size).to_i32
        args << @i32.const_int(index)
        # TODO: handle case where final_fn is present (pony_alloc_small_final)
        @builder.call(@mod.functions["pony_alloc_small"], args, "#{name}_buf")
      else
        args << @intptr.const_int(size)
        # TODO: handle case where final_fn is present (pony_alloc_large_final)
        @builder.call(@mod.functions["pony_alloc_large"], args, "#{name}_buf")
      end
    
    value = @builder.bit_cast(value, gtype.structure.pointer, name)
    gen_put_desc(value, gtype, name)
    
    value
  end
  
  def gen_put_desc(value, gtype, name = "")
    raise NotImplementedError.new(gtype) unless gtype.type_def.has_desc?
    
    desc_p = @builder.struct_gep(value, 0, "#{name}_desc_p")
    @builder.store(gtype.desc, desc_p)
    # TODO: tbaa? (from set_descriptor in libponyc/codegen/gencall.c)
  end
end
