require "llvm"

##
# The purpose of the Run pass is to run the program built by the Binary pass.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps temporary state (on the stack) at the program level.
# This pass produces output state at the program level (the exit code).
# !! This pass has the side-effect of executing the program.
#
class Savi::Compiler::Run
  getter! exitcode : Int32

  def run(ctx)
    target = Target.new(ctx.code_gen.target_machine.triple)
    bin_path = Binary.path_for(ctx)
    bin_path += ".exe" if target.windows?

    res = Process.run("/usr/bin/env", [bin_path], output: STDOUT, error: STDERR)
    @exitcode = res.exit_code
  end
end
