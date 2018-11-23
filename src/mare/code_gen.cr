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
      # Get the return value from the end of the function body, as an I32.
      ret_val = f.body.last.as(AST::LiteralInteger).value.to_i32
      
      # Declare the main function.
      main = @mod.functions.add("main", ([] of LLVM::Type), @llvm.int32)
      main.linkage = LLVM::Linkage::External
      
      # Write the return statement just inside the main block.
      bb = main.basic_blocks.append("entry")
      @builder.position_at_end bb
      @builder.ret(@llvm.int32.const_int(ret_val))
      
      # Run the function!
      res = LLVM::JITCompiler.new @mod do |jit|
        jit.run_function(@mod.functions["main"], @llvm).to_i
      end
    end
    
    ctx.finish
    
    res
  end
end
