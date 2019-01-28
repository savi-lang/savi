require "llvm"

class Mare::Compiler::Eval
  getter! exitcode : Int32
  
  def self.run(ctx)
    new.run(ctx)
  end
  
  def run(ctx)
    ctx.program.eval = self
    
    mod = ctx.program.code_gen.mod
    llvm = ctx.program.code_gen.llvm
    
    # TODO: Should this pass be responsible for generating the wrapper function?
    jit_func = mod.functions["__mare_jit"]
    
    # Run the function!
    LLVM::JITCompiler.new mod do |jit|
      @exitcode = jit.run_function(jit_func, llvm).to_i
    end
  end
end
