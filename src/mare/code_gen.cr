require "llvm"

lib LibLLVM
  fun const_inbounds_gep = LLVMConstInBoundsGEP(value : ValueRef, indices : ValueRef*, num_indices : UInt32) : ValueRef
  fun set_unnamed_addr = LLVMSetUnnamedAddr(global : ValueRef, is_unnamed_addr : Int32)
  fun is_unnamed_addr = LLVMIsUnnamedAddr(global : ValueRef) : Int32
end

class LLVM::Context
  def const_inbounds_gep(value : Value, indices : Array(Value))
    Value.new LibLLVM.const_inbounds_gep(value, indices.to_unsafe.as(LibLLVM::ValueRef*), indices.size)
  end
end

struct LLVM::Value
  def unnamed_addr=(unnamed_addr)
    LibLLVM.set_unnamed_addr(self, unnamed_addr ? 1 : 0)
  end
  
  def unnamed_addr?
    LibLLVM.is_unnamed_addr(self) != 0
  end
end

class Mare::CodeGen
  @llvm : LLVM::Context
  @mod : LLVM::Module
  @builder : LLVM::Builder
  
  getter return_value
  
  def initialize
    LLVM.init_x86
    @llvm = LLVM::Context.new
    @mod = @llvm.new_module("minimal")
    @builder = @llvm.new_builder
    @return_value = 0
    
    @ptr   = @llvm.int8.pointer.as(LLVM::Type)
    @i32   = @llvm.int32.as(LLVM::Type)
    @i32_0 = @llvm.int32.const_int(0).as(LLVM::Value)
  end
  
  def run(ctx = Context)
    # CodeGen for all FFI declarations.
    ctx.program.types.each do |t|
      next unless t.kind == Program::Type::Kind::FFI
      t.functions.each { |f| gen_ffi_decl(f) }
    end
    
    # Find the main function.
    f = ctx.program.find_func!("Main", "main")
    
    # Declare the main function.
    main = @mod.functions.add("main", ([] of LLVM::Type), @i32)
    main.linkage = LLVM::Linkage::External
    
    # Create a basic block to hold the implementation of the main function.
    bb = main.basic_blocks.append("entry")
    @builder.position_at_end bb
    
    # Call gen_expr on each expression, treating the last one as the return.
    ret_val = nil
    f.body.each { |expr| ret_val = gen_expr(expr) }
    raise "main is an empty function" unless ret_val
    @builder.ret(ret_val)
    
    # Run the function!
    @return_value = LLVM::JITCompiler.new @mod do |jit|
      jit.run_function(@mod.functions["main"], @llvm).to_i
    end
  end
  
  def ffi_type_for(ident)
    case ident.value
    when "I32"     then @i32
    when "CString" then @ptr
    else raise NotImplementedError.new(ident.value)
    end
  end
  
  def gen_ffi_decl(f)
    params = f.params.not_nil!.terms.map do |param|
      ffi_type_for(param.as(AST::Identifier))
    end
    ret = ffi_type_for(f.ret.not_nil!)
    @mod.functions.add(f.ident.value, params, ret)
  end
  
  def gen_ffi_calls(relate)
    raise NotImplementedError.new(relate.terms.size) if relate.terms.size != 3
    
    # TODO: Assemble this earlier in Compiler::Default?
    iter = relate.terms.each
    lhs = iter.next.as(AST::Identifier)
    op = iter.next.as(AST::Operator)
    rhs = iter.next.as(AST::Qualify)
    
    raise NotImplementedError.new(lhs.value) if lhs.value != "LibC"
    
    ffi_name = rhs.terms[0].as(AST::Identifier).value
    call_args = rhs.group.terms.map { |expr| gen_expr(expr).as(LLVM::Value) }
    @builder.call(@mod.functions[ffi_name], call_args)
  end
  
  def gen_expr(expr) : LLVM::Value
    case expr
    when AST::LiteralInteger
      # TODO: Allow for non-I32 integers, based on inference.
      @i32.const_int(expr.value.to_i32)
    when AST::LiteralString
      @llvm.const_inbounds_gep(gen_string_global(expr), [@i32_0, @i32_0])
    when AST::Relate
      # TODO: handle all cases of stuff here...
      if expr.terms[1].as(AST::Operator).value == "."
        gen_ffi_calls(expr)
      else raise NotImplementedError.new(expr.inspect)
      end
    else
      raise NotImplementedError.new(expr.inspect)
    end
  end
  
  def gen_string_global(expr : AST::LiteralString) : LLVM::Value
    # TODO: Use a string table here to avoid redundant const global strings.
    value = @llvm.const_string(expr.value)
    global = @mod.globals.add(value.type, "")
    global.linkage = LLVM::Linkage::External
    global.initializer = value
    global.global_constant = true
    global.unnamed_addr = true
    global
  end
end
