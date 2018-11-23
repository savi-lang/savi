require "llvm"

class Mare::CodeGen
  @llvm : LLVM::Context
  @mod : LLVM::Module
  @builder : LLVM::Builder
  
  def initialize
    LLVM.init_x86
    @llvm = LLVM::Context.new
    @mod = @llvm.new_module("minimal")
    @builder = @llvm.new_builder
  end
  
  def run(ctx = Context)
    res = 0
    
    ctx.on Compiler::Default::Function, ["fun", "Main", "main"] do |f|
      # Declare the main function.
      main = @mod.functions.add("main", ([] of LLVM::Type), @llvm.int32)
      main.linkage = LLVM::Linkage::External
      
      # Create a basic block to hold the implementation of the main function.
      bb = main.basic_blocks.append("entry")
      @builder.position_at_end bb
      
      # Call gen_expr on each expression, treating the last one as the ret_val.
      ret_val = nil
      f.body.each { |expr| ret_val = gen_expr(expr) }
      raise "main is an empty function" unless ret_val
      @builder.ret(ret_val)
      
      # Run the function!
      res = LLVM::JITCompiler.new @mod do |jit|
        jit.run_function(@mod.functions["main"], @llvm).to_i
      end
    end
    
    ctx.finish
    
    res
  end
  
  def gen_expr(expr) : LLVM::Value
    case expr
    when AST::LiteralInteger
      # TODO: Allow for non-I32 integers, based on inference.
      @llvm.int32.const_int(expr.value.to_i32)
    else
      raise NotImplementedError.new(expr.inspect)
    end
  end
end
