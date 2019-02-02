require "llvm"
require "random"
require "../ext/llvm" # TODO: get these merged into crystal standard library
require "compiler/crystal/config" # TODO: remove
require "./code_gen/*"

class Mare::Compiler::CodeGen
  getter llvm : LLVM::Context
  getter target : LLVM::Target
  getter target_machine : LLVM::TargetMachine
  getter mod : LLVM::Module
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
    getter type_def : Reach::Def
    getter gfuncs : Hash(String, GenFunc)
    getter fields : Array(Tuple(String, Reach::Ref))
    getter vtable_size : Int32
    getter desc_type : LLVM::Type
    getter struct_type : LLVM::Type
    getter! desc : LLVM::Value
    getter! singleton : LLVM::Value
    
    def initialize(g : CodeGen, @type_def)
      @gfuncs = Hash(String, GenFunc).new
      @fields = Array(Tuple(String, Reach::Ref)).new
      
      # Take down info on all functions and fields.
      @vtable_size = 0
      @type_def.each_function.each do |f|
        if f.has_tag?(:field)
          field_type = g.program.reach[f.infer.resolve(f.ident)]
          @fields << {f.ident.value, field_type}
        else
          next unless g.program.reach.reached_func?(f)
          
          vtable_index = g.program.paint[f]
          @vtable_size = (vtable_index + 1) if @vtable_size <= vtable_index
          
          key = f.ident.value
          key += Random::Secure.hex if f.has_tag?(:hygienic)
          @gfuncs[key] = GenFunc.new(@type_def, f, vtable_index)
        end
      end
      
      # Generate descriptor type and struct type.
      @desc_type = g.gen_desc_type(@type_def, @vtable_size)
      @struct_type = g.gen_struct_type(@type_def, @desc_type, @fields)
    end
    
    # Generate function declarations.
    def gen_func_decls(g : CodeGen)
      # Generate associated function declarations, some of which
      # may be referenced in the descriptor global instance below.
      @gfuncs.each_value do |gfunc|
        g.gen_func_decl(self, gfunc)
      end
    end
    
    # Generate virtual call table.
    def gen_vtable(g : CodeGen) : Array(LLVM::Value)
      ptr = g.llvm.int8.pointer
      vtable = Array(LLVM::Value).new(@vtable_size, ptr.null)
      @gfuncs.each_value do |gfunc|
        vtable[gfunc.vtable_index] =
          g.llvm.const_bit_cast(gfunc.virtual_llvm_func.to_value, ptr)
      end
      vtable
    end
    
    # Generate descriptor global instance.
    def gen_desc(g : CodeGen)
      return if @type_def.is_abstract?
      
      @desc = g.gen_desc(@type_def, @desc_type, gen_vtable(g))
    end
    
    # Generate function implementations.
    def gen_func_impls(g : CodeGen)
      return if @type_def.is_abstract?
      
      @gfuncs.each_value do |gfunc|
        g.gen_func_impl(self, gfunc)
      end
    end
    
    # Generate other global values.
    def gen_globals(g : CodeGen)
      return if @type_def.is_abstract?
      
      @singleton = g.gen_singleton(@type_def, @struct_type, @desc.not_nil!)
    end
    
    def [](name)
      @gfuncs[name]
    end
    
    def struct_ptr
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
    getter vtable_index : Int32
    getter llvm_name : String
    property! llvm_func : LLVM::Function
    property! virtual_llvm_func : LLVM::Function
    
    def initialize(type_def : Reach::Def, @func, @vtable_index)
      @needs_receiver = \
        type_def.has_state? &&
        !@func.has_tag?(:constructor) &&
        !@func.has_tag?(:constant)
      
      @llvm_name = "#{type_def.llvm_name}.#{@func.ident.value}"
      @llvm_name = "#{@llvm_name}.HYGIENIC" if func.has_tag?(:hygienic)
    end
    
    def needs_receiver?
      @needs_receiver
    end
    
    def is_initializer?
      func.has_tag?(:field) && !func.body.nil?
    end
  end
  
  getter! program : Program
  
  def initialize
    LLVM.init_x86
    @target_triple = Crystal::Config.default_target_triple
    @target = LLVM::Target.from_triple(@target_triple)
    @target_machine = @target.create_target_machine(@target_triple).as(LLVM::TargetMachine)
    @llvm = LLVM::Context.new
    @mod = @llvm.new_module("main")
    @builder = @llvm.new_builder
    @di = DebugInfo.new(@llvm, @mod, @builder)
    
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
    @f32     = @llvm.float.as(LLVM::Type)
    @f64     = @llvm.double.as(LLVM::Type)
    @intptr  = @llvm.intptr(@target_machine.data_layout).as(LLVM::Type)
    
    @frames = [] of Frame
    @string_globals = {} of String => LLVM::Value
    @gtypes = {} of String => GenType
    
    # Pony runtime types.
    @desc = @llvm.opaque_struct("_.DESC").as(LLVM::Type)
    @desc_ptr = @desc.pointer.as(LLVM::Type)
    @obj = @llvm.opaque_struct("_.OBJECT").as(LLVM::Type)
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
    gen_desc_basetype
    @obj.struct_set_body([@desc_ptr])
    
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
    program.reach[inferred]
  end
  
  def llvm_type_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    llvm_type_of(type_of(expr, in_gfunc))
  end
  
  def llvm_type_of(gtype : GenType)
    llvm_type_of(gtype.type_def.as_ref)
  end
  
  def llvm_type_of(ref : Reach::Ref)
    case ref.llvm_use_type
    when :i1 then @i1
    when :i8, :u8 then @i8
    when :i32, :u32 then @i32
    when :i64, :u64 then @i64
    when :f32 then @f32
    when :f64 then @f64
    when :ptr then @ptr
    when :struct_ptr then
      @gtypes[program.reach[ref.single!].llvm_name].struct_ptr
    when :object_ptr then
      @obj_ptr
    else raise NotImplementedError.new(ref.llvm_use_type)
    end
  end
  
  def llvm_mem_type_of(ref : Reach::Ref)
    case ref.llvm_mem_type
    when :i1 then @i8 # TODO: test that this works okay 
    when :i8, :u8 then @i8
    when :i32, :u32 then @i32
    when :i64, :u64 then @i64
    when :ptr then @ptr
    when :struct_ptr then
      @gtypes[program.reach[ref.single!].llvm_name].struct_ptr
    when :object_ptr then
      @obj_ptr
    else raise NotImplementedError.new(ref.llvm_mem_type)
    end
  end
  
  def gtype_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    llvm_name = program.reach[type_of(expr, in_gfunc).single!].llvm_name
    @gtypes[llvm_name]
  end
  
  def gtypes_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    type_of(expr, in_gfunc).each_defn.map do |defn|
      llvm_name = program.reach[defn].llvm_name
      @gtypes[llvm_name]
    end.to_a
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
    ctx.program.reach.each_type_def.each do |type_def|
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
    
    # Finish up debugging info.
    @di.finish
    
    # Run LLVM sanity checks on the generated module.
    begin
      @mod.verify
    rescue ex
      @mod.dump
      raise ex
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
    vtable_index = @gtypes["Main"]["new"].vtable_index
    msg_size = @target_machine.data_layout.abi_size(msg_type)
    pool_index = PonyRT.pool_index(msg_size)
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
      @i32.const_int(PonyRT::TRACE_IMMUTABLE),
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
    
    # Add debug info for this function
    @di.func_start(gfunc) if gfunc
    
    # Create an entry block and start building from there.
    @builder.position_at_end(gen_block("entry"))
  end
  
  def gen_func_end
    @di.func_end if @di.in_func?
    
    @frames.pop
  end
  
  def gen_within_foreign_frame(gtype : GenType, gfunc : GenFunc)
    @frames << Frame.new(self, gfunc.llvm_func, gtype, gfunc)
    
    yield
    
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
  
  def gen_func_decl(gtype, gfunc)
    # Get the LLVM type to use for the return type.
    ret_type = llvm_type_of(gfunc.func.ident, gfunc)
    
    # Get the LLVM types to use for the parameter types.
    param_types = [] of LLVM::Type
    gfunc.func.params.try do |params|
      params.terms.map do |param|
        param_types << llvm_type_of(param, gfunc)
      end
    end
    
    # Add implicit receiver parameter if needed.
    param_types.unshift(llvm_type_of(gtype)) if gfunc.needs_receiver?
    
    # Store the function declaration.
    gfunc.llvm_func = @mod.functions.add(gfunc.llvm_name, param_types, ret_type)
    
    # If we used a receiver parameter, we're done.
    # Otherwise, we need to create a wrapper method for the vtable that
    # includes a receiver parameter, but throws it away without using it.
    gfunc.virtual_llvm_func =
      if gfunc.needs_receiver?
        gfunc.llvm_func
      else
        vtable_name = "#{gfunc.llvm_name}.VIRTUAL"
        param_types.unshift(gtype.struct_ptr)
        
        @mod.functions.add vtable_name, param_types, ret_type do |fn|
          gen_func_start(fn)
          
          forward_args =
            (param_types.size - 1).times.map { |i| fn.params[i + 1] }.to_a
          
          @builder.ret @builder.call(gfunc.llvm_func, forward_args)
          
          gen_func_end
        end
      end
  end
  
  def gen_func_impl(gtype, gfunc)
    return gen_intrinsic(gtype, gfunc) if gfunc.func.has_tag?(:compiler_intrinsic)
    return gen_ffi_body(gtype, gfunc) if gfunc.func.has_tag?(:ffi)
    
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
    last_expr = nil
    last_value = nil
    gfunc.func.body.not_nil!.terms.each do |expr|
      last_expr = expr
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
  
  def gen_intrinsic(gtype, gfunc)
    raise NotImplementedError.new(gtype.type_def) \
      unless gtype.type_def.is_numeric?
    
    gen_func_start(gfunc.llvm_func)
    params = gfunc.llvm_func.params
    
    @builder.ret \
      case gfunc.func.ident.value
      when "==" then
        if gtype.type_def.is_floating_point_numeric?
          @builder.fcmp(LLVM::RealPredicate::OEQ, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::EQ, params[0], params[1])
        end
      when "!=" then
        if gtype.type_def.is_floating_point_numeric?
          @builder.fcmp(LLVM::RealPredicate::ONE, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::NE, params[0], params[1])
        end
      when "<" then
        if gtype.type_def.is_floating_point_numeric?
          @builder.fcmp(LLVM::RealPredicate::OLT, params[0], params[1])
        elsif gtype.type_def.is_signed_numeric?
          @builder.icmp(LLVM::IntPredicate::SLT, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::ULT, params[0], params[1])
        end
      when "<=" then
        if gtype.type_def.is_floating_point_numeric?
          @builder.fcmp(LLVM::RealPredicate::OLE, params[0], params[1])
        elsif gtype.type_def.is_signed_numeric?
          @builder.icmp(LLVM::IntPredicate::SLE, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::ULE, params[0], params[1])
        end
      when ">" then
        if gtype.type_def.is_floating_point_numeric?
          @builder.fcmp(LLVM::RealPredicate::OGT, params[0], params[1])
        elsif gtype.type_def.is_signed_numeric?
          @builder.icmp(LLVM::IntPredicate::SGT, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::UGT, params[0], params[1])
        end
      when ">=" then
        if gtype.type_def.is_floating_point_numeric?
          @builder.fcmp(LLVM::RealPredicate::OGE, params[0], params[1])
        elsif gtype.type_def.is_signed_numeric?
          @builder.icmp(LLVM::IntPredicate::SGE, params[0], params[1])
        else
          @builder.icmp(LLVM::IntPredicate::UGE, params[0], params[1])
        end
      when "+" then
        if gtype.type_def.is_floating_point_numeric?
          @builder.fadd(params[0], params[1])
        else
          @builder.add(params[0], params[1])
        end
      when "-" then
        if gtype.type_def.is_floating_point_numeric?
          @builder.fsub(params[0], params[1])
        else
          @builder.sub(params[0], params[1])
        end
      when "*" then
        if gtype.type_def.is_floating_point_numeric?
          @builder.fmul(params[0], params[1])
        else
          @builder.mul(params[0], params[1])
        end
      when "/", "%" then
        if gtype.type_def.is_floating_point_numeric?
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
            if gtype.type_def.is_signed_numeric?
          after_block = gen_block(".div.after")
          
          blocks = [] of LLVM::BasicBlock
          values = [] of LLVM::Value
          
          # Return zero if dividing by zero.
          nonzero = @builder.icmp LLVM::IntPredicate::NE, params[1], zero,
            "#{params[1].name}.nonzero"
          @builder.cond(nonzero, nonzero_block, after_block)
          blocks << @builder.insert_block
          values << zero
          @builder.position_at_end(nonzero_block)
          
          # If signed, return zero if this operation would overflow.
          # This happens for exactly one case in each signed integer type.
          # In `I8`, the overflow case is `-128 / -1`, which would be 128.
          if gtype.type_def.is_signed_numeric?
            bad = @builder.not(zero)
            denom_good = @builder.icmp LLVM::IntPredicate::NE, params[1], bad,
              "#{params[1].name}.nonoverflow"
            
            bits = llvm_type.const_int(gtype.type_def.bit_width - 1)
            bad = @builder.shl(bad, bits)
            numer_good = @builder.icmp LLVM::IntPredicate::NE, params[0], bad,
              "#{params[0].name}.nonoverflow"
            
            either_good = @builder.or(numer_good, denom_good, "nonoverflow")
            
            @builder.cond(either_good, nonoverflow_block.not_nil!, after_block)
            blocks << @builder.insert_block
            values << zero
            @builder.position_at_end(nonoverflow_block.not_nil!)
          end
          
          # Otherwise, compute the result.
          result =
            case {gtype.type_def.is_signed_numeric?, gfunc.func.ident.value}
            when {true, "/"} then @builder.sdiv(params[0], params[1])
            when {true, "%"} then @builder.srem(params[0], params[1])
            when {false, "/"} then @builder.udiv(params[0], params[1])
            when {false, "%"} then @builder.urem(params[0], params[1])
            else raise NotImplementedError.new(gtype.type_def.llvm_name)
            end
          result.name = "result"
          @builder.br(after_block)
          blocks << @builder.insert_block
          values << result
          @builder.position_at_end(after_block)
          
          # Get the final result, which may be zero from one of the pre-checks.
          @builder.phi(llvm_type, blocks, values, "phidiv")
        end
      else
        raise NotImplementedError.new(gfunc.func.ident.inspect)
      end
    
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
    
    lhs_gtypes = gtypes_of(relate.lhs)
    
    # Even if there are multiple possible gtypes and thus gfuncs, we choose an
    # arbitrary one for the purposes of checking arg types against param types.
    # We make the assumption that signature differences have been prevented.
    lhs_gtype = lhs_gtypes.first
    gfunc = lhs_gtype[member]
    
    # For any args we are missing, try to find and use a default param value.
    gfunc.func.params.try do |params|
      while args.size < params.terms.size
        param = params.terms[args.size]
        
        raise "missing arg #{args.size + 1} with no default param" \
          unless param.is_a?(AST::Relate) && param.op.value == "DEFAULTPARAM"
        
        gen_within_foreign_frame lhs_gtype, gfunc do
          args << gen_expr(param.rhs)
        end
      end
    end
    
    # Generate code for the receiver, whether we actually use it or not.
    # We trust LLVM optimizations to eliminate dead code when it does nothing.
    receiver = gen_expr(relate.lhs)
    
    # Call the LLVM function, or do a virtual call if necessary.
    @di.set_loc(relate.op)
    needs_virtual_call = lhs_gtypes.size > 1 || lhs_gtype.type_def.is_abstract?
    if needs_virtual_call
      gen_virtual_call(receiver, args, lhs_gtypes, gfunc)
    else
      args.unshift(receiver) if gfunc.needs_receiver?
      @builder.call(gfunc.llvm_func, args)
    end
  end
  
  def gen_virtual_call(
    receiver : LLVM::Value,
    args : Array(LLVM::Value),
    gtypes : Array(GenType),
    gfunc : GenFunc,
  )
    receiver.name = gtypes.map(&.type_def).map(&.llvm_name).join("|") \
      if receiver.name.empty?
    rname = receiver.name
    fname = "#{rname}.#{gfunc.func.ident.value}"
    
    # Load the type descriptor of the receiver so we can read its vtable,
    # then load the function pointer from the appropriate index of that vtable.
    desc = gen_get_desc(receiver)
    vtable_gep = @builder.struct_gep(desc, DESC_VTABLE, "#{rname}.DESC.VTABLE")
    vtable_idx = @i32.const_int(gfunc.vtable_index)
    gep = @builder.inbounds_gep(vtable_gep, @i32_0, vtable_idx, "#{fname}.GEP")
    load = @builder.load(gep, "#{fname}.LOAD")
    func = @builder.bit_cast(load, gfunc.virtual_llvm_func.type, fname)
    
    # Cast the receiver to right type and prepend it to our args list.
    rtype = gfunc.virtual_llvm_func.params.first.type
    args.unshift(@builder.bit_cast(receiver, rtype, "#{rname}.CAST"))
    
    @builder.call(func, args)
  end
  
  def gen_eq(relate)
    ref = func_frame.refer[relate.lhs]
    value = gen_expr(relate.rhs).as(LLVM::Value)
    
    value = @builder.bit_cast(value, llvm_type_of(relate.lhs), value.name)
    
    @di.set_loc(relate.op)
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
  
  def gen_check_subtype(relate)
    lhs = gen_expr(relate.lhs)
    rhs = gen_expr(relate.rhs) # TODO: should this be removed?
    rhs_type = type_of(relate.rhs)
    
    # TODO: support abstract gtypes
    raise NotImplementedError.new(rhs_type) unless rhs_type.is_concrete?
    rhs_gtype = @gtypes[program.reach[rhs_type.single!].llvm_name]
    
    lhs_desc = gen_get_desc(lhs)
    rhs_desc = gen_get_desc(rhs_gtype)
    
    @builder.icmp LLVM::IntPredicate::EQ, lhs_desc, rhs_desc,
      "#{lhs.name}<:#{rhs.name}"
  end
  
  def gen_expr(expr, const_only = false) : LLVM::Value
    @di.set_loc(expr)
    
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
      elsif ref.is_a?(Refer::Decl) || ref.is_a?(Refer::DeclAlias)
        enum_value = ref.defn.metadata[:enum_value]?
        if enum_value
          llvm_type_of(expr).const_int(enum_value.as(Int32))
        elsif ref.final_decl.defn.has_tag?(:numeric)
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
    when AST::LiteralFloat
      gen_float(expr)
    when AST::LiteralString
      gen_string(expr)
    when AST::Relate
      raise "#{expr.inspect} isn't a constant value" if const_only
      case expr.op.as(AST::Operator).value
      when "." then gen_dot(expr)
      when "=" then gen_eq(expr)
      when "<:" then gen_check_subtype(expr)
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
    when :f32 then @f32.const_float(expr.value.to_f32)
    when :f64 then @f64.const_double(expr.value.to_f64)
    else raise "invalid numeric literal type: #{type_ref}"
    end
  end
  
  def gen_float(expr : AST::LiteralFloat)
    type_ref = type_of(expr)
    case type_ref.llvm_use_type
    when :f32 then @f32.const_float(expr.value.to_f32)
    when :f64 then @f64.const_double(expr.value.to_f64)
    else raise "invalid floating point literal type: #{type_ref}"
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
  
  # TODO: Use infer resolution for static True/False finding where possible.
  def gen_choice(expr : AST::Choice)
    raise NotImplementedError.new(expr.inspect) if expr.list.empty?
    
    # Get the LLVM type for the phi that joins the final value of each branch.
    # Each such value will needed to be bitcast to the that type.
    phi_type = llvm_type_of(expr)
    
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
    cond_value = gen_expr(expr.list.first[0])
    
    # Generate the interacting code for each consecutive pair of cases.
    values = [] of LLVM::Value
    blocks = [] of LLVM::BasicBlock
    expr.list.each_cons(2).to_a.each_with_index do |(fore, aft), i|
      # The case block is the body to execute if the cond_value is true.
      # Otherwise we will jump to the next block, with its next cond_value.
      case_block = case_and_cond_blocks.shift
      next_block = case_and_cond_blocks.shift
      @builder.cond(cond_value, case_block, next_block)
      
      # Generate code for the case block that we execute, finishing by
      # jumping to the post block using the `br` instruction, where we will
      # carry the value we just generated as one of the possible phi values.
      @builder.position_at_end(case_block)
      value = gen_expr(fore[1])
      value = @builder.bit_cast(value, phi_type, "#{value.name}.CAST")
      values << value
      blocks << case_block
      @builder.br(post_block)
      
      # Generate code for the next block, which is the condition to be
      # checked for truthiness in the next iteration of this loop
      # (or ignored if this is the final case, which must always be exhaustive).
      @builder.position_at_end(next_block)
      cond_value = gen_expr(aft[0])
    end
    
    # This is the final case block - we will jump to it unconditionally,
    # regardless of the truthiness of the preceding cond_value.
    # Choices must always be typechecked to be exhaustive, so we can rest
    # on the guarantee that this cond_value will always be true if we reach it.
    case_block = case_and_cond_blocks.shift
    @builder.br(case_block)
    
    # Generate code for the final case block using exactly the same strategy
    # that we used when we generated case blocks inside the loop above.
    @builder.position_at_end(case_block)
    value = gen_expr(expr.list.last[1])
    value = @builder.bit_cast(value, phi_type, "#{value.name}.CAST")
    values << value
    blocks << case_block
    @builder.br(post_block)
    
    # Here at the post block, we receive the value that was returned by one of
    # the cases above, using the LLVM mechanism called a "phi" instruction.
    @builder.position_at_end(post_block)
    @builder.phi(phi_type, blocks, values, "phichoice")
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
      @pptr,                          # 14: TODO: traits
      @pptr,                          # 15: TODO: fields
      @ptr.array(0),                  # 16: vtable
    ]
  end
  
  def gen_desc_type(type_def : Reach::Def, vtable_size : Int32) : LLVM::Type
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
      @ptr.array(vtable_size),        # 16: vtable
    ], "#{type_def.llvm_name}.DESC"
  end
  
  def gen_desc(type_def, desc_type, vtable)
    desc = @mod.globals.add(desc_type, "#{type_def.llvm_name}.DESC")
    desc.linkage = LLVM::Linkage::LinkerPrivate
    desc.global_constant = true
    desc
    
    case type_def.llvm_name
    when "Main"
      dispatch_fn = @mod.functions.add("#{type_def.llvm_name}.DISPATCH", @dispatch_fn)
      
      traits = @pptr.null # TODO
      fields = @pptr.null # TODO
    else
      dispatch_fn = @dispatch_fn_ptr.null # TODO
      traits = @pptr.null # TODO
      fields = @pptr.null # TODO
    end
    
    desc.initializer = desc_type.const_struct [
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
      @ptr.const_array(vtable),              # 16: vtable
    ]
    
    if dispatch_fn.is_a?(LLVM::Function)
      dispatch_fn = dispatch_fn.not_nil!
      
      dispatch_fn.unnamed_addr = true
      dispatch_fn.call_convention = LLVM::CallConvention::C
      dispatch_fn.linkage = LLVM::Linkage::External
      
      gen_func_start(dispatch_fn)
      
      msg_id_gep = @builder.struct_gep(dispatch_fn.params[2], 1, "msg.id")
      msg_id = @builder.load(msg_id_gep)
      
      # TODO: ... ^
      
      # TODO: arguments
      # TODO: don't special-case this
      @builder.call(@gtypes["Main"]["new"].llvm_func)
      
      @builder.ret
      
      gen_func_end
    end
    
    desc
  end
  
  def gen_struct_type(type_def, desc_type, fields)
    elements = [] of LLVM::Type
    elements << desc_type.pointer # even types with no desc have a global desc
    elements << @actor_pad if type_def.has_actor_pad?
    
    fields.each { |name, t| elements << llvm_mem_type_of(t) }
    
    @llvm.struct(elements, type_def.llvm_name)
  end
  
  def gen_singleton(type_def, struct_type, desc)
    global = @mod.globals.add(struct_type, type_def.llvm_name)
    global.linkage = LLVM::Linkage::LinkerPrivate
    global.global_constant = true
    
    # For allocated types, we still generate a singleton for static use,
    # but we need to populate the fields with something - we use zeros.
    # We are relying on the reference capabilities part of the type system
    # to prevent such singletons from ever having their fields dereferenced.
    elements = struct_type.struct_element_types[1..-1].map(&.null)
    
    # The first element is always the type descriptor.
    elements.unshift(desc)
    
    global.initializer = struct_type.const_struct(elements)
    global
  end
  
  def gen_alloc(gtype, name = "@")
    raise NotImplementedError.new(gtype.type_def) \
      unless gtype.type_def.has_allocation?
    
    size = gtype.type_def.abi_size
    size = 1 if size == 0
    args = [pony_ctx]
    
    value =
      if size <= PonyRT::HEAP_MAX
        index = PonyRT.heap_index(size).to_i32
        args << @i32.const_int(index)
        # TODO: handle case where final_fn is present (pony_alloc_small_final)
        @builder.call(@mod.functions["pony_alloc_small"], args, "#{name}.MEM")
      else
        args << @intptr.const_int(size)
        # TODO: handle case where final_fn is present (pony_alloc_large_final)
        @builder.call(@mod.functions["pony_alloc_large"], args, "#{name}.MEM")
      end
    
    value = @builder.bit_cast(value, gtype.struct_ptr, name)
    gen_put_desc(value, gtype, name)
    
    value
  end
  
  def gen_get_desc(gtype_name : String)
    gen_get_desc(@gtypes[gtype_name])
  end
  
  def gen_get_desc(gtype : GenType)
    @llvm.const_bit_cast(gtype.desc, @desc_ptr)
  end
  
  def gen_get_desc(value : LLVM::Value)
    value_type = value.type
    raise "not a struct pointer: #{value}" \
      unless value_type.kind == LLVM::Type::Kind::Pointer \
        && value_type.element_type.kind == LLVM::Type::Kind::Struct
    
    desc_gep = @builder.struct_gep(value, 0, "#{value.name}.DESC")
    @builder.load(desc_gep, "#{value.name}.DESC.LOAD")
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
    @builder.load(gep, "@.#{name}.LOAD")
  end
  
  def gen_field_store(name, value)
    gtype = func_frame.gtype.not_nil!
    object = func_frame.receiver_value
    gep = @builder.struct_gep(object, gtype.field_index(name), "@.#{name}")
    @builder.store(value, gep)
  end
end
