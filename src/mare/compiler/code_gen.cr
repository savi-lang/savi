require "llvm"
require "random"
require "../ext/llvm" # TODO: get these merged into crystal standard library
require "compiler/crystal/config" # TODO: remove
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
      @g.ctx.refers[@gfunc.as(GenFunc).func]
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
      
      # Take down info on all fields.
      @fields = @type_def.fields
      
      # Take down info on all functions.
      @vtable_size = 0
      @type_def.each_function.each do |f|
        next if f.has_tag?(:field)
        next unless g.ctx.reach.reached_func?(f)
        
        vtable_index = g.ctx.paint[f]
        @vtable_size = (vtable_index + 1) if @vtable_size <= vtable_index
        
        key = f.ident.value
        key += Random::Secure.hex if f.has_tag?(:hygienic)
        @gfuncs[key] = GenFunc.new(@type_def, f, vtable_index)
      end
      
      # If we're generating for a type that has no inherent descriptor,
      # we are generating a struct_type for the boxed container that gets used
      # when that value has to be passed as an abstract reference with a desc.
      # In this case, there should be just a single field - the value itself.
      if !type_def.has_desc?
        raise "a value type with no descriptor can't have fields" \
          unless @fields.empty?
        
        @fields << {"VALUE", @type_def.as_ref}
      end
      
      # Generate descriptor type and struct type.
      @desc_type = g.gen_desc_type(@type_def, @vtable_size)
      @struct_type = g.llvm.struct_create_named(@type_def.llvm_name).as(LLVM::Type)
    end
    
    # Generate struct type bodies.
    def gen_struct_type(g : CodeGen)
      g.gen_struct_type(@struct_type, @type_def, @desc_type, @fields)
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
    
    # Generate other global values.
    def gen_globals(g : CodeGen)
      return if @type_def.is_abstract?
      
      @singleton = g.gen_singleton(@type_def, @struct_type, @desc.not_nil!)
    end
    
    # Generate function implementations.
    def gen_func_impls(g : CodeGen)
      return if @type_def.is_abstract?
      
      g.gen_dispatch_impl(self) if @type_def.is_actor?
      
      @gfuncs.each_value do |gfunc|
        g.gen_send_impl(self, gfunc) if gfunc.needs_send?
        g.gen_func_impl(self, gfunc)
      end
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
    property! send_llvm_func : LLVM::Function
    property! send_msg_llvm_type : LLVM::Type
    
    def initialize(type_def : Reach::Def, @func, @vtable_index)
      @needs_receiver = type_def.has_state? && !(@func.cap.value == "non")
      
      @llvm_name = "#{type_def.llvm_name}.#{@func.ident.value}"
      @llvm_name = "#{@llvm_name}.HYGIENIC" if func.has_tag?(:hygienic)
    end
    
    def needs_receiver?
      @needs_receiver
    end
    
    def needs_send?
      @func.has_tag?(:async)
    end
    
    def is_initializer?
      func.has_tag?(:field) && !func.body.nil?
    end
  end
  
  getter! ctx : Context
  
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
    
    @void     = @llvm.void.as(LLVM::Type)
    @ptr      = @llvm.int8.pointer.as(LLVM::Type)
    @pptr     = @llvm.int8.pointer.pointer.as(LLVM::Type)
    @i1       = @llvm.int1.as(LLVM::Type)
    @i1_false = @llvm.int1.const_int(0).as(LLVM::Value)
    @i1_true  = @llvm.int1.const_int(1).as(LLVM::Value)
    @i8       = @llvm.int8.as(LLVM::Type)
    @i32      = @llvm.int32.as(LLVM::Type)
    @i32_ptr  = @llvm.int32.pointer.as(LLVM::Type)
    @i32_0    = @llvm.int32.const_int(0).as(LLVM::Value)
    @i64      = @llvm.int64.as(LLVM::Type)
    @f32      = @llvm.float.as(LLVM::Type)
    @f64      = @llvm.double.as(LLVM::Type)
    @intptr   = @llvm.intptr(@target_machine.data_layout).as(LLVM::Type)
    
    @frames = [] of Frame
    @string_globals = {} of String => LLVM::Value
    @cstring_globals = {} of String => LLVM::Value
    @gtypes = {} of String => GenType
    
    # Pony runtime types.
    @desc = @llvm.struct_create_named("_.DESC").as(LLVM::Type)
    @desc_ptr = @desc.pointer.as(LLVM::Type)
    @obj = @llvm.struct_create_named("_.OBJECT").as(LLVM::Type)
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
    inferred = ctx.infers[in_gfunc.func].resolve(expr)
    ctx.reach[inferred]
  end
  
  def llvm_type_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    llvm_type_of(type_of(expr, in_gfunc))
  end
  
  def llvm_type_of(gtype : GenType)
    llvm_type_of(gtype.type_def.as_ref) # TODO: this is backwards - defs should have a llvm_use_type of their own, with refs delegating to that implementation when there is a singular meta_type
  end
  
  def llvm_type_of(ref : Reach::Ref)
    case ref.llvm_use_type
    when :i1 then @i1
    when :i8 then @i8
    when :i32 then @i32
    when :i64 then @i64
    when :f32 then @f32
    when :f64 then @f64
    when :ptr then @ptr
    when :struct_ptr then
      @gtypes[ctx.reach[ref.single!].llvm_name].struct_ptr
    when :object_ptr then
      @obj_ptr
    else raise NotImplementedError.new(ref.llvm_use_type)
    end
  end
  
  def llvm_mem_type_of(ref : Reach::Ref)
    case ref.llvm_mem_type
    when :i1 then @i8 # TODO: test that this works okay 
    when :i8 then @i8
    when :i32 then @i32
    when :i64 then @i64
    when :f32 then @f32
    when :f64 then @f64
    when :ptr then @ptr
    when :struct_ptr then
      @gtypes[ctx.reach[ref.single!].llvm_name].struct_ptr
    when :object_ptr then
      @obj_ptr
    else raise NotImplementedError.new(ref.llvm_mem_type)
    end
  end
  
  def gtype_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    llvm_name = ctx.reach[type_of(expr, in_gfunc).single!].llvm_name
    @gtypes[llvm_name]
  end
  
  def gtypes_of(expr : AST::Node, in_gfunc : GenFunc? = nil)
    type_of(expr, in_gfunc).each_defn.map do |defn|
      llvm_name = ctx.reach[defn].llvm_name
      @gtypes[llvm_name]
    end.to_a
  end
  
  def pony_ctx
    return func_frame.pony_ctx if func_frame.pony_ctx?
    func_frame.pony_ctx = @builder.call(@mod.functions["pony_ctx"], "PONY_CTX")
  end
  
  def run(ctx : Context)
    @ctx = ctx
    
    # Generate all type descriptors and function declarations.
    ctx.reach.each_type_def.each do |type_def|
      @gtypes[type_def.llvm_name] = GenType.new(self, type_def)
    end
    
    # Generate all struct types.
    @gtypes.each_value(&.gen_struct_type(self))
    
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
    @builder.store(gen_cstring("marejit"), argv_0)
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
      gen_cstring("Error: couldn't start the runtime!")
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
    ident = ident.as(AST::Identifier)
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
    
    # Constructors return void (the caller already has the receiver).
    ret_type = @void if gfunc.func.has_tag?(:constructor)
    
    # Get the LLVM types to use for the parameter types.
    param_types = [] of LLVM::Type
    mparam_types = [] of LLVM::Type if gfunc.needs_send?
    gfunc.func.params.try do |params|
      params.terms.map do |param|
        ref = type_of(param, gfunc)
        param_types << llvm_type_of(ref)
        mparam_types << llvm_mem_type_of(ref) if mparam_types
      end
    end
    
    # Add implicit receiver parameter if needed.
    param_types.unshift(llvm_type_of(gtype)) if gfunc.needs_receiver?
    
    # Store the function declaration.
    gfunc.llvm_func = @mod.functions.add(gfunc.llvm_name, param_types, ret_type)
    
    # If we didn't use a receiver parameter in the function signature,
    # we need to create a wrapper method for the virtual table that
    # includes a receiver parameter, but throws it away without using it.
    gfunc.virtual_llvm_func =
      if gfunc.needs_receiver?
        gfunc.llvm_func
      else
        vtable_name = "#{gfunc.llvm_name}.VIRTUAL"
        param_types.unshift(gtype.struct_ptr)
        
        @mod.functions.add vtable_name, param_types, ret_type do |fn|
          next if gtype.type_def.is_abstract?
          
          gen_func_start(fn)
          
          forward_args =
            (param_types.size - 1).times.map { |i| fn.params[i + 1] }.to_a
          
          @builder.ret @builder.call(gfunc.llvm_func, forward_args)
          
          gen_func_end
        end
      end
    
    # If this is an async function, we need to generate a wrapper that sends
    # it as a message to be handled asynchronously by the dispatch function.
    # This is also the function that should go in the virtual table.
    if gfunc.needs_send?
      send_name = "#{gfunc.llvm_name}.SEND"
      msg_name = "#{gfunc.llvm_name}.SEND.MSG"
      
      # We'll fill in the implementation of this later, in gen_send_impl.
      gfunc.virtual_llvm_func = gfunc.send_llvm_func =
        @mod.functions.add(send_name, param_types, @gtypes["None"].struct_ptr)
      
      # We also need to create a message type to use in the send operation.
      gfunc.send_msg_llvm_type =
        @llvm.struct([@i32, @i32, @ptr] + mparam_types.not_nil!, msg_name)
    end
  end
  
  def gen_func_impl(gtype, gfunc)
    return gen_intrinsic(gtype, gfunc) if gfunc.func.has_tag?(:compiler_intrinsic)
    return gen_ffi_impl(gtype, gfunc) if gfunc.func.has_tag?(:ffi)
    
    # Fields with no initializer body can be skipped.
    return if gfunc.func.has_tag?(:field) && gfunc.func.body.nil?
    
    gen_func_start(gfunc.llvm_func, gtype, gfunc)
    
    # Set a receiver value (the value of the self in this function).
    func_frame.receiver_value =
      if gfunc.needs_receiver?
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
    
    # For a constructor, return void (the caller already has the receiver).
    if gfunc.func.has_tag?(:constructor)
      last_value = nil
    else
      last_value.not_nil!
    end
    
    # Return the return value (or void).
    last_value ? @builder.ret(last_value) : @builder.ret
    
    gen_func_end
  end
  
  def gen_ffi_decl(gfunc)
    params = gfunc.func.params.not_nil!.terms.map do |param|
      ffi_type_for(param.as(AST::Identifier))
    end
    ret = ffi_type_for(gfunc.func.ret.not_nil!)
    
    ffi_link_name = gfunc.func.metadata[:ffi_link_name].as(String)
    
    # Prevent double-declaring for common FFI functions already known to us.
    llvm_ffi_func = @mod.functions[ffi_link_name]?
    if llvm_ffi_func
      # TODO: verify that parameter types and return type are compatible
      return @mod.functions[ffi_link_name]
    end
    
    @mod.functions.add(ffi_link_name, params, ret)
  end
  
  def gen_ffi_impl(gtype, gfunc)
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
      when "u8" then gen_numeric_conv(gtype, @gtypes["U8"], params[0])
      when "u32" then gen_numeric_conv(gtype, @gtypes["U32"], params[0])
      when "u64" then gen_numeric_conv(gtype, @gtypes["U64"], params[0])
      when "i8" then gen_numeric_conv(gtype, @gtypes["I8"], params[0])
      when "i32" then gen_numeric_conv(gtype, @gtypes["I32"], params[0])
      when "i64" then gen_numeric_conv(gtype, @gtypes["I64"], params[0])
      when "f32" then gen_numeric_conv(gtype, @gtypes["F32"], params[0])
      when "f64" then gen_numeric_conv(gtype, @gtypes["F64"], params[0])
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
      when "bit_and"
        raise "bit_and float" if gtype.type_def.is_floating_point_numeric?
        @builder.and(params[0], params[1])
      when "bit_or"
        raise "bit_or float" if gtype.type_def.is_floating_point_numeric?
        @builder.or(params[0], params[1])
      when "bit_xor"
        raise "bit_xor float" if gtype.type_def.is_floating_point_numeric?
        @builder.xor(params[0], params[1])
      when "invert"
        raise "invert float" if gtype.type_def.is_floating_point_numeric?
        @builder.not(params[0])
      when "reverse_bits"
        raise "reverse_bits float" if gtype.type_def.is_floating_point_numeric?
        op_func =
          case gtype.type_def.bit_width
          when 1
            @mod.functions["llvm.bitreverse.i1"]? ||
              @mod.functions.add("llvm.bitreverse.i1", [@i1], @i1)
          when 8
            @mod.functions["llvm.bitreverse.i8"]? ||
              @mod.functions.add("llvm.bitreverse.i8", [@i8], @i8)
          when 32
            @mod.functions["llvm.bitreverse.i32"]? ||
              @mod.functions.add("llvm.bitreverse.i32", [@i32], @i32)
          when 64
            @mod.functions["llvm.bitreverse.i64"]? ||
              @mod.functions.add("llvm.bitreverse.i64", [@i64], @i64)
          else raise NotImplementedError.new(gtype.type_def.bit_width)
          end
        @builder.call(op_func, [params[0]])
      when "swap_bytes"
        raise "swap_bytes float" if gtype.type_def.is_floating_point_numeric?
        case gtype.type_def.bit_width
        when 1, 8
          params[0]
        when 32
          op_func =
            @mod.functions["llvm.bswap.i32"]? ||
              @mod.functions.add("llvm.bswap.i32", [@i32], @i32)
          @builder.call(op_func, [params[0]])
        when 64
          op_func =
            @mod.functions["llvm.bswap.i64"]? ||
              @mod.functions.add("llvm.bswap.i64", [@i64], @i64)
          @builder.call(op_func, [params[0]])
        else raise NotImplementedError.new(gtype.type_def.bit_width)
        end
      when "leading_zeros"
        raise "leading_zeros float" if gtype.type_def.is_floating_point_numeric?
        op_func =
          case gtype.type_def.bit_width
          when 1
            @mod.functions["llvm.ctlz.i1"]? ||
              @mod.functions.add("llvm.ctlz.i1", [@i1, @i1], @i1)
          when 8
            @mod.functions["llvm.ctlz.i8"]? ||
              @mod.functions.add("llvm.ctlz.i8", [@i8, @i1], @i8)
          when 32
            @mod.functions["llvm.ctlz.i32"]? ||
              @mod.functions.add("llvm.ctlz.i32", [@i32, @i1], @i32)
          when 64
            @mod.functions["llvm.ctlz.i64"]? ||
              @mod.functions.add("llvm.ctlz.i64", [@i64, @i1], @i64)
          else raise NotImplementedError.new(gtype.type_def.bit_width)
          end
        gen_numeric_conv gtype, @gtypes["U8"],
          @builder.call(op_func, [params[0], @i1_false])
      when "trailing_zeros"
        raise "trailing_zeros float" if gtype.type_def.is_floating_point_numeric?
        op_func =
          case gtype.type_def.bit_width
          when 1
            @mod.functions["llvm.cttz.i1"]? ||
              @mod.functions.add("llvm.cttz.i1", [@i1, @i1], @i1)
          when 8
            @mod.functions["llvm.cttz.i8"]? ||
              @mod.functions.add("llvm.cttz.i8", [@i8, @i1], @i8)
          when 32
            @mod.functions["llvm.cttz.i32"]? ||
              @mod.functions.add("llvm.cttz.i32", [@i32, @i1], @i32)
          when 64
            @mod.functions["llvm.cttz.i64"]? ||
              @mod.functions.add("llvm.cttz.i64", [@i64, @i1], @i64)
          else raise NotImplementedError.new(gtype.type_def.bit_width)
          end
        gen_numeric_conv gtype, @gtypes["U8"],
          @builder.call(op_func, [params[0], @i1_false])
      when "count_ones"
        raise "count_ones float" if gtype.type_def.is_floating_point_numeric?
        op_func =
          case gtype.type_def.bit_width
          when 1
            @mod.functions["llvm.ctpop.i1"]? ||
              @mod.functions.add("llvm.ctpop.i1", [@i1], @i1)
          when 8
            @mod.functions["llvm.ctpop.i8"]? ||
              @mod.functions.add("llvm.ctpop.i8", [@i8], @i8)
          when 32
            @mod.functions["llvm.ctpop.i32"]? ||
              @mod.functions.add("llvm.ctpop.i32", [@i32], @i32)
          when 64
            @mod.functions["llvm.ctpop.i64"]? ||
              @mod.functions.add("llvm.ctpop.i64", [@i64], @i64)
          else raise NotImplementedError.new(gtype.type_def.bit_width)
          end
        gen_numeric_conv gtype, @gtypes["U8"], \
          @builder.call(op_func, [params[0]])
      when "bits"
        raise "bits integer" unless gtype.type_def.is_floating_point_numeric?
        case gtype.type_def.bit_width
        when 32 then @builder.bit_cast(params[0], @i32)
        when 64 then @builder.bit_cast(params[0], @i64)
        else raise NotImplementedError.new(gtype.type_def.bit_width)
        end
      when "from_bits"
        raise "from_bits integer" unless gtype.type_def.is_floating_point_numeric?
        case gtype.type_def.bit_width
        when 32 then @builder.bit_cast(params[0], @f32)
        when 64 then @builder.bit_cast(params[0], @f64)
        else raise NotImplementedError.new(gtype.type_def.bit_width)
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
      arg_exprs = [] of AST::Node
    when AST::Qualify
      member = rhs.term.as(AST::Identifier).value
      args = rhs.group.terms.map { |expr| gen_expr(expr).as(LLVM::Value) }
      arg_exprs = rhs.group.terms.dup
    else raise NotImplementedError.new(rhs)
    end
    
    lhs_type = type_of(relate.lhs)
    
    # Even if there are multiple possible gtypes and thus gfuncs, we choose an
    # arbitrary one for the purposes of checking arg types against param types.
    # We make the assumption that signature differences have been prevented.
    lhs_gtype = @gtypes[ctx.reach[lhs_type.any_callable_defn_for(member)].llvm_name] # TODO: simplify this mess of an expression
    gfunc = lhs_gtype[member]
    
    # For any args we are missing, try to find and use a default param value.
    gfunc.func.params.try do |params|
      while args.size < params.terms.size
        param = params.terms[args.size]
        
        raise "missing arg #{args.size + 1} with no default param" \
          unless param.is_a?(AST::Relate) && param.op.value == "DEFAULTPARAM"
        
        gen_within_foreign_frame lhs_gtype, gfunc do
          args << gen_expr(param.rhs)
          arg_exprs << param.rhs
        end
      end
    end
    
    # Generate code for the receiver, whether we actually use it or not.
    # We trust LLVM optimizations to eliminate dead code when it does nothing.
    receiver = gen_expr(relate.lhs)
    
    # Determine if we need to use a virtual call here.
    needs_virtual_call = lhs_type.is_abstract?
    
    # If this is a constructor, the receiver must be allocated first.
    if gfunc.func.has_tag?(:constructor)
      raise "can't do a virtual call on a constructor" if needs_virtual_call
      receiver = gen_alloc(lhs_gtype, "#{lhs_gtype.type_def.llvm_name}.new")
    end
    
    # Prepend the receiver to the args list if necessary.
    if gfunc.needs_receiver? || needs_virtual_call || gfunc.needs_send?
      args.unshift(receiver)
      arg_exprs.unshift(relate.lhs)
    end
    
    # Call the LLVM function, or do a virtual call if necessary.
    @di.set_loc(relate.op)
    result =
      if needs_virtual_call
        gen_virtual_call(receiver, args, arg_exprs, lhs_type, gfunc)
      elsif gfunc.needs_send?
        gen_call(gfunc.send_llvm_func, args, arg_exprs)
      else
        gen_call(gfunc.llvm_func, args, arg_exprs)
      end
    
    # If this is a constructor, the result is the receiver we already have.
    result = receiver if gfunc.func.has_tag?(:constructor)
    
    result
  end
  
  def gen_virtual_call(
    receiver : LLVM::Value,
    args : Array(LLVM::Value),
    arg_exprs : Array(AST::Node),
    type_ref : Reach::Ref,
    gfunc : GenFunc,
  )
    receiver.name = type_ref.show_type if receiver.name.empty?
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
    
    gen_call(func, gfunc.virtual_llvm_func, args, arg_exprs)
  end
  
  def gen_call(
    func : LLVM::Function,
    args : Array(LLVM::Value),
    arg_exprs : Array(AST::Node),
  )
    # Cast the arguments to the right types.
    cast_args = func.params.to_a.zip(args).zip(arg_exprs)
      .map { |(param, arg), expr| gen_assign_cast(arg, param.type, expr) }
    
    @builder.call(func, cast_args)
  end
  
  def gen_call(
    func : LLVM::Value,
    func_proto : LLVM::Function,
    args : Array(LLVM::Value),
    arg_exprs : Array(AST::Node),
  )
    # This version of gen_call uses a separate func_proto as the prototype,
    # which we use to get the parameter types to cast the arguments to.
    cast_args = func_proto.params.to_a.zip(args).zip(arg_exprs)
      .map { |(param, arg), expr| gen_assign_cast(arg, param.type, expr) }
    
    @builder.call(func, cast_args)
  end
  
  def gen_eq(relate)
    ref = func_frame.refer[relate.lhs]
    value = gen_expr(relate.rhs).as(LLVM::Value)
    name = value.name
    
    value = gen_assign_cast(value, llvm_type_of(relate.lhs), relate.rhs)
    value.name = name
    
    @di.set_loc(relate.op)
    if ref.is_a?(Refer::Local)
      raise "local already declared: #{ref.inspect}" \
        if func_frame.current_locals[ref]?
      
      value.name = ref.name
      func_frame.current_locals[ref] = value
    else raise NotImplementedError.new(relate.inspect)
    end
  end
  
  def gen_field_eq(node : AST::FieldWrite)
    value = gen_expr(node.rhs).as(LLVM::Value)
    name = value.name
    
    value = gen_assign_cast(value, llvm_type_of(node), node.rhs)
    value.name = name
    
    @di.set_loc(node)
    gen_field_store(node.value, value)
    value
  end
  
  def gen_check_subtype(relate)
    lhs = gen_expr(relate.lhs)
    rhs = gen_expr(relate.rhs) # TODO: should this be removed?
    rhs_type = type_of(relate.rhs)
    
    # TODO: support abstract gtypes
    raise NotImplementedError.new(rhs_type) unless rhs_type.is_concrete?
    rhs_gtype = @gtypes[ctx.reach[rhs_type.single!].llvm_name]
    
    lhs_desc = gen_get_desc(lhs)
    rhs_desc = gen_get_desc(rhs_gtype)
    
    @builder.icmp LLVM::IntPredicate::EQ, lhs_desc, rhs_desc,
      "#{lhs.name}<:#{rhs.name}"
  end
  
  def gen_assign_cast(
    value : LLVM::Value,
    to_type : LLVM::Type,
    from_expr : AST::Node?,
  )
    from_type = value.type
    return value if from_type == to_type
    
    case to_type.kind
    when LLVM::Type::Kind::Integer,
         LLVM::Type::Kind::Half,
         LLVM::Type::Kind::Float,
         LLVM::Type::Kind::Double
      # This happens for example with Bool when llvm_use_type != llvm_mem_type,
      # for cases where we are assigning to or from a field.
      # TODO: Implement this and verify it is working as intended.
      raise NotImplementedError.new("zero extension / truncation in cast") \
        if from_type.kind == LLVM::Type::Kind::Integer \
        && to_type.kind == LLVM::Type::Kind::Integer \
        && to_type.int_width != from_type.int_width
      
      # This is just an assertion to make sure the type system protected us
      # from trying to implicitly cast between different numeric types.
      # We should only be going to/from a boxed pointer container.
      raise "can't cast to/from different numeric types implicitly" \
        if from_type.kind != LLVM::Type::Kind::Pointer
      
      # Unwrap the box and finish the assign cast from there.
      # This brings us to the zero extension / truncation logic above.
      value = gen_unboxed(value, from_expr.not_nil!)
      gen_assign_cast(value, to_type, from_expr)
    when LLVM::Type::Kind::Pointer
      # If we're going from pointer to non-pointer, we're unboxing,
      # so we have to do that first before the LLVM bit cast.
      value = gen_boxed(value, from_expr.not_nil!) \
        if value.type.kind != LLVM::Type::Kind::Pointer
      
      # Do the LLVM bitcast.
      @builder.bit_cast(value, to_type, "#{value.name}.CAST")
    else
      raise NotImplementedError.new(to_type.kind)
    end
  end
  
  def gen_boxed(value, from_expr)
    # Allocate a struct pointer to hold the type descriptor and value.
    # This also writes the type descriptor into it appropriate position.
    boxed = gen_alloc(gtype_of(from_expr), "#{value.name}.BOXED")
    
    # Write the value itself into the value field of the struct.
    value_gep = @builder.struct_gep(boxed, 1, "#{value.name}.BOXED.VALUE")
    @builder.store(value, value_gep)
    
    # Return the struct pointer
    boxed
  end
  
  def gen_unboxed(value, from_expr)
    # First, cast the given object pointer to the correct boxed struct pointer.
    struct_ptr = gtype_of(from_expr).struct_ptr
    value = @builder.bit_cast(value, struct_ptr, "#{value.name}.BOXED")
    
    # Load the value itself into the value field of the boxed struct pointer.
    value_gep = @builder.struct_gep(value, 1, "#{value.name}.VALUE")
    @builder.load(value_gep, "#{value.name}.VALUE.LOAD")
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
    when AST::FieldRead
      gen_field_load(expr.value)
    when AST::FieldWrite
      gen_field_eq(expr)
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
    when :i1 then @i1.const_int(expr.value.to_i8)
    when :i8 then @i8.const_int(expr.value.to_i8)
    when :i32 then @i32.const_int(expr.value.to_i32)
    when :i64 then @i64.const_int(expr.value.to_i64)
    when :f32 then @f32.const_float(expr.value.to_f32)
    when :f64 then @f64.const_double(expr.value.to_f64)
    else raise "invalid numeric literal type: #{type_ref.inspect}"
    end
  end
  
  def gen_float(expr : AST::LiteralFloat)
    type_ref = type_of(expr)
    case type_ref.llvm_use_type
    when :f32 then @f32.const_float(expr.value.to_f32)
    when :f64 then @f64.const_double(expr.value.to_f64)
    else raise "invalid floating point literal type: #{type_ref.inspect}"
    end
  end
  
  def gen_numeric_conv(
    from_gtype : GenType,
    to_gtype : GenType,
    value : LLVM::Value,
  )
    from_signed = from_gtype.type_def.is_signed_numeric?
    to_signed = to_gtype.type_def.is_signed_numeric?
    from_float = from_gtype.type_def.is_floating_point_numeric?
    to_float = to_gtype.type_def.is_floating_point_numeric?
    from_width = from_gtype.type_def.bit_width
    to_width = to_gtype.type_def.bit_width
    
    to_llvm_type = llvm_type_of(to_gtype)
    
    if from_float && to_float
      if from_width < to_width
        @builder.fpext(value, to_llvm_type)
      elsif from_width > to_width
        raise "unexpected from_width: #{from_width}" unless from_width == 64
        raise "unexpected to_width: #{to_width}" unless to_width == 32
        gen_numeric_conv_f64_to_f32(value)
      else
        value
      end
    elsif from_float && to_signed
      case from_width
      when 32 then gen_numeric_conv_f32_to_sint(value, to_llvm_type)
      when 64 then gen_numeric_conv_f64_to_sint(value, to_llvm_type)
      else raise NotImplementedError.new(from_width)
      end
    elsif from_float
      case from_width
      when 32 then gen_numeric_conv_f32_to_uint(value, to_llvm_type)
      when 64 then gen_numeric_conv_f64_to_uint(value, to_llvm_type)
      else raise NotImplementedError.new(from_width)
      end
    elsif from_signed && to_float
      @builder.si2fp(value, to_llvm_type)
    elsif to_float
      @builder.ui2fp(value, to_llvm_type)
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
    @builder.position_at_end(nan)
    
    return non_nan
  end
  
  def gen_numeric_conv_float_handle_overflow_saturate(
    value : LLVM::Value,
    from_type : LLVM::Type,
    to_type : LLVM::Type,
    to_min : LLVM::Value,
    to_max : LLVM::Value,
    is_signed : Bool,
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
    @builder.position_at_end(overflow)
    @builder.ret(to_max)
    
    # Check if the floating-point value underflows the minimum integer value.
    @builder.position_at_end(test_underflow)
    to_fmin =
      if is_signed
        @builder.si2fp(to_min, from_type)
      else
        @builder.ui2fp(to_min, from_type)
      end
    is_underflow = @builder.fcmp(LLVM::RealPredicate::OLT, value, to_fmin)
    @builder.cond(is_underflow, underflow, normal)
    
    # If it does underflow, return the minimum integer value.
    @builder.position_at_end(underflow)
    @builder.ret(to_min)
    
    # Otherwise, proceed with the conversion as normal.
    @builder.position_at_end(normal)
    if is_signed
      @builder.fp2si(value, to_type)
    else
      @builder.fp2ui(value, to_type)
    end
  end
  
  def gen_numeric_conv_f64_to_f32(value : LLVM::Value)
    # If the value is F64 NaN, return F32 NaN.
    test_overflow = gen_numeric_conv_float_handle_nan(
      value, @i64, 0x7FF0000000000000, 0x000FFFFFFFFFFFFF)
    @builder.ret(@llvm.const_bit_cast(@i32.const_int(0x7FC00000), @f32))
    
    overflow = gen_block("overflow")
    test_underflow = gen_block("test_underflow")
    underflow = gen_block("underflow")
    normal = gen_block("normal")
    
    # Check if the F64 value overflows the maximum F32 value.
    @builder.position_at_end(test_overflow)
    f32_max = @llvm.const_bit_cast(@i32.const_int(0x7F7FFFFF), @f32)
    f32_max = @builder.fpext(f32_max, @f64, "f32_max")
    is_overflow = @builder.fcmp(LLVM::RealPredicate::OGT, value, f32_max)
    @builder.cond(is_overflow, overflow, test_underflow)
    
    # If it does overflow, return positive infinity.
    @builder.position_at_end(overflow)
    @builder.ret(@llvm.const_bit_cast(@i32.const_int(0x7F800000), @f32))
    
    # Check if the F64 value underflows the minimum F32 value.
    @builder.position_at_end(test_underflow)
    f32_min = @llvm.const_bit_cast(@i32.const_int(0xFF7FFFFF), @f32)
    f32_min = @builder.fpext(f32_min, @f64, "f32_min")
    is_underflow = @builder.fcmp(LLVM::RealPredicate::OLT, value, f32_min)
    @builder.cond(is_underflow, underflow, normal)
    
    # If it does underflow, return negative infinity.
    @builder.position_at_end(underflow)
    @builder.ret(@llvm.const_bit_cast(@i32.const_int(0xFF800000), @f32))
    
    # Otherwise, proceed with the floating-point truncation as normal.
    @builder.position_at_end(normal)
    @builder.fptrunc(value, @f32)
  end
  
  def gen_numeric_conv_f32_to_sint(value : LLVM::Value, to_type : LLVM::Type)
    test_overflow = gen_numeric_conv_float_handle_nan(
      value, @i32, 0x7F800000, 0x007FFFFF)
    @builder.ret(to_type.const_int(0))
    
    @builder.position_at_end(test_overflow)
    to_min = @builder.not(to_type.const_int(0), "to_min.pre")
    to_max = @builder.lshr(to_min, to_type.const_int(1), "to_max")
    to_min = @builder.xor(to_max, to_min, "to_min")
    gen_numeric_conv_float_handle_overflow_saturate(
      value, @f32, to_type, to_min, to_max, true)
  end
  
  def gen_numeric_conv_f64_to_sint(value : LLVM::Value, to_type : LLVM::Type)
    test_overflow = gen_numeric_conv_float_handle_nan(
      value, @i64, 0x7FF0000000000000, 0x000FFFFFFFFFFFFF)
    @builder.ret(to_type.const_int(0))
    
    @builder.position_at_end(test_overflow)
    to_min = @builder.not(to_type.const_int(0), "to_min.pre")
    to_max = @builder.lshr(to_min, to_type.const_int(1), "to_max")
    to_min = @builder.xor(to_max, to_min, "to_min")
    gen_numeric_conv_float_handle_overflow_saturate(
      value, @f64, to_type, to_min, to_max, true)
  end
  
  def gen_numeric_conv_f32_to_uint(value : LLVM::Value, to_type : LLVM::Type)
    test_overflow = gen_numeric_conv_float_handle_nan(
      value, @i32, 0x7F800000, 0x007FFFFF)
    @builder.ret(to_type.const_int(0))
    
    @builder.position_at_end(test_overflow)
    to_min = to_type.const_int(0)
    to_max = @builder.not(to_min, "to_max")
    gen_numeric_conv_float_handle_overflow_saturate(
      value, @f32, to_type, to_min, to_max, false)
  end
  
  def gen_numeric_conv_f64_to_uint(value : LLVM::Value, to_type : LLVM::Type)
    test_overflow = gen_numeric_conv_float_handle_nan(
      value, @i64, 0x7FF0000000000000, 0x000FFFFFFFFFFFFF)
    @builder.ret(to_type.const_int(0))
    
    @builder.position_at_end(test_overflow)
    to_min = to_type.const_int(0)
    to_max = @builder.not(to_min, "to_max")
    gen_numeric_conv_float_handle_overflow_saturate(
      value, @f64, to_type, to_min, to_max, false)
  end
  
  def gen_cstring(value : String) : LLVM::Value
    @llvm.const_inbounds_gep(
      @cstring_globals.fetch value do
        const = @llvm.const_string(value)
        global = @mod.globals.add(const.type, "")
        global.linkage = LLVM::Linkage::External # TODO: Private linkage?
        global.initializer = const
        global.global_constant = true
        global.unnamed_addr = true
        
        @cstring_globals[value] = global
      end,
      [@i32_0, @i32_0],
    )
  end
  
  def gen_string(expr : AST::LiteralString)
    value = expr.value
    
    @string_globals.fetch value do
      string_gtype = @gtypes["String"]
      const = string_gtype.struct_type.const_struct [
        string_gtype.desc,
        @i64.const_int(value.size),
        @i64.const_int(value.size + 1),
        gen_cstring(value),
      ]
      
      global = @mod.globals.add(const.type, "")
      global.linkage = LLVM::Linkage::External # TODO: Private linkage?
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
      value = gen_assign_cast(value, phi_type, fore[1])
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
    value = gen_assign_cast(value, phi_type, expr.list.last[1])
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
    
    dispatch_fn =
      if type_def.is_actor?
        @mod.functions.add("#{type_def.llvm_name}.DISPATCH", @dispatch_fn)
      else
        @dispatch_fn_ptr.null
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
      @pptr.null,                            # 14: TODO: traits
      @pptr.null,                            # 15: TODO: fields
      @ptr.const_array(vtable),              # 16: vtable
    ]
    
    desc
  end
  
  def gen_struct_type(struct_type, type_def, desc_type, fields)
    elements = [] of LLVM::Type
    elements << desc_type.pointer # even types with no desc have a global desc
    elements << @actor_pad if type_def.has_actor_pad?
    
    fields.each { |name, t| elements << llvm_mem_type_of(t) }
    
    struct_type.struct_set_body(elements)
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
  
  def gen_alloc(gtype, name)
    return gen_alloc_actor(gtype, name) if gtype.type_def.is_actor?
    
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
  
  def gen_alloc_actor(gtype, name)
    allocated = @builder.call(@mod.functions["pony_create"], [
      pony_ctx,
      gen_get_desc(gtype),
    ], "#{name}.MEM")
    
    @builder.bit_cast(allocated, gtype.struct_ptr, name)
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
  
  def gen_send_impl(gtype, gfunc)
    fn = gfunc.send_llvm_func
    gen_func_start(fn)
    
    # Get the message type and virtual table index to use.
    msg_type = gfunc.send_msg_llvm_type
    vtable_index = gfunc.vtable_index
    
    # Allocate a message object of the specific size/type used by this function.
    msg_size = @target_machine.data_layout.abi_size(msg_type)
    pool_index = PonyRT.pool_index(msg_size)
    msg_opaque = @builder.call(@mod.functions["pony_alloc_msg"],
      [@i32.const_int(pool_index), @i32.const_int(vtable_index)], "msg_opaque")
    msg = @builder.bit_cast(msg_opaque, msg_type.pointer, "msg")
    
    # Store all forwarding arguments in the message object.
    msg_type.struct_element_types.each_with_index do |elem_type, i|
      next if i < 3 # skip the first 3 boilerplate fields in the message
      param = fn.params[i - 3 + 1] # skip 3 fields, skip 1 param (the receiver)
      
      # Cast the argument to the correct type and store it in the message.
      cast_arg = gen_assign_cast(param, elem_type, nil)
      arg_gep = @builder.struct_gep(msg, i)
      @builder.store(cast_arg, arg_gep)
    end
    
    # TODO: Trace the message.
    
    # Send the message.
    @builder.call(@mod.functions["pony_sendv_single"], [
      pony_ctx,
      @builder.bit_cast(fn.params[0], @obj_ptr), # TODO: no fallback || here
      msg_opaque,
      msg_opaque,
      @i1.const_int(1)
    ])
    
    # Return None.
    @builder.ret(gen_none)
    
    gen_func_end
  end
  
  def gen_dispatch_impl(gtype : GenType)
    # Get the reference to the dispatch function declared earlier.
    # We'll fill in the implementation of that function now.
    fn = @mod.functions["#{gtype.type_def.llvm_name}.DISPATCH"]
    fn.unnamed_addr = true
    fn.call_convention = LLVM::CallConvention::C
    fn.linkage = LLVM::Linkage::External
    
    gen_func_start(fn)
    
    # Get the receiver pointer from the second parameter (index 1).
    receiver = @builder.bit_cast(fn.params[1], gtype.struct_ptr)
    
    # Get the message id from the first field of the message object
    # (which was the third parameter to this function).
    msg_id_gep = @builder.struct_gep(fn.params[2], 1, "msg.id")
    msg_id = @builder.load(msg_id_gep)
    receiver = @builder.bit_cast(fn.params[1], gtype.struct_ptr, "@")
    
    # Capture the current insert block so we can come back to it later,
    # after we jump around into each case block that we need to generate.
    orig_block = @builder.insert_block
    
    # Generate the case block for each async function of this type,
    # mapped by the message id that corresponds to that function.
    cases = {} of LLVM::Value => LLVM::BasicBlock
    gtype.gfuncs.each do |func_name, gfunc|
      # Only look at functions with the async tag.
      next unless gfunc.func.has_tag?(:async)
      
      # Use the vtable index of the function as the message id to look for.
      id = @i32.const_int(gfunc.vtable_index)
      
      # Create the block to execute when the message id matches.
      cases[id] = block = gen_block("DISPATCH.#{func_name}")
      @builder.position_at_end(block)
      
      # Destructure args from the message.
      msg_type = gfunc.send_msg_llvm_type
      msg = @builder.bit_cast(fn.params[2], msg_type.pointer)
      args =
        msg_type.struct_element_types.each_with_index.map do |(elem_type, i)|
          next if i < 3 # skip the first 3 boilerplate fields in the message
          arg_gep = @builder.struct_gep(msg, i)
          gen_assign_cast(@builder.load(arg_gep), elem_type, nil)
        end.to_a.compact
      
      # Prepend the receiver as the first argument, not included in the message.
      args.unshift(receiver)
      
      # TODO: Trace the message.
      
      # Call the underlying function and return void.
      @builder.call(gfunc.llvm_func, args)
      @builder.ret
    end
    
    # We rely on the typechecker to not let us call undefined async functions,
    # so the "else" case of this switch block is to be considered unreachable.
    unreachable_block = gen_block("unreachable_block")
    @builder.position_at_end(unreachable_block)
    # TODO: LLVM infinite loop protection workaround (see gentype.c:503)
    @builder.unreachable
    
    # Finally, return to the original block that we came from and create the
    # switch that maps onto all the case blocks that we just generated.
    @builder.position_at_end(orig_block)
    @builder.switch(msg_id, unreachable_block, cases)
    
    gen_func_end
  end
end
