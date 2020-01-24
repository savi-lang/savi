require "file"
require "llvm"

##
# The purpose of the Binary pass is to produce a binary executable of the
# program, using LLVM and clang tooling and writing the result to disk.
# The difference between this pass and the Binary pass is that this version
# of the pass uses the Verona runtime instead of the Pony runtime.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps temporary state (on the stack) at the program level.
# This pass produces no output state (aside from the side effect below).
# !! This pass has the side-effect of writing files to disk.
#
class Mare::Compiler::BinaryVerona
  VERONA_STATIC_LIB = "/usr/lib/libverona-sys-static.a"

  def self.run(ctx)
    new.run(ctx)
  end

  def run(ctx)
    llvm = ctx.code_gen_verona.llvm
    machine = ctx.code_gen_verona.target_machine
    mod = ctx.code_gen_verona.mod

    bin_filename = File.tempname(".mare.user.program")
    obj_filename = "#{bin_filename}.o"

    machine.emit_obj_to_file(mod, obj_filename)

    puts obj_filename

    link_args = %w{clang++
      -fuse-ld=lld -rdynamic -static -fpic
      -lc -pthread -ldl -latomic -lexecinfo
    }
    link_args << obj_filename
    link_args << VERONA_STATIC_LIB
    link_args << "-o" << "main" # TODO: customizable output binary filename

    res = Process.run("/usr/bin/env", link_args, output: STDOUT, error: STDERR)
    raise "linker failed" unless res.exit_status == 0
  ensure
    File.delete(obj_filename) if obj_filename
  end

  def self.run_last_compiled_program
    res = Process.run("/usr/bin/env", ["./main"], output: STDOUT, error: STDERR)
    res.exit_status
  end
end
