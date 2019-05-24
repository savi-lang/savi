require "llvm"

##
# The purpose of the Eval pass is to run the program using LLVM's JIT compiler.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps temporary state (on the stack) at the program level.
# This pass produces output state at the program level (the exit code).
# !! This pass has the side-effect of executing the program.
#
class Mare::Compiler::Eval
  getter! exitcode : Int32
  
  def run(ctx)
    mod = ctx.code_gen.mod
    llvm = ctx.code_gen.llvm
    
    # TODO: Should this pass be responsible for generating the wrapper function?
    jit_func = mod.functions["__mare_jit"]
    
    # Run the function!
    LLVM::JITCompiler.new mod do |jit|
      @exitcode = jit.run_function(jit_func, llvm).to_i
    end
  end
end
