require "llvm"

##
# The purpose of the Eval pass is to run the program built by the Binary pass.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps temporary state (on the stack) at the program level.
# This pass produces output state at the program level (the exit code).
# !! This pass has the side-effect of executing the program.
#
class Savi::Compiler::Eval
  getter! exitcode : Int32

  def run(ctx)
    binary_path = "./#{ctx.options.binary_name}"

    res = Process.run("/usr/bin/env", [binary_path], output: STDOUT, error: STDERR)
    @exitcode = res.exit_status
  end
end
