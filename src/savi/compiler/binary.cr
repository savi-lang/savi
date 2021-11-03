require "file"
require "llvm"

##
# The purpose of the Binary pass is to produce a binary executable of the
# program, using LLVM and clang tooling and writing the result to disk.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps temporary state (on the stack) at the program level.
# This pass produces no output state (aside from the side effect below).
# !! This pass has the side-effect of writing files to disk.
#
class Savi::Compiler::Binary
  def self.run(ctx)
    new.run(ctx)
  end

  def run(ctx)
    # Compile a temporary binary object file, that we will remove after we
    # use it in the linker invocation to create the final binary.
    obj_filename = File.tempname(".savi.user.program") + ".o"
    BinaryObject.run(ctx, obj_filename)

    target = Target.new(ctx.code_gen.target_machine.triple)
    link_args = if target.freebsd?
                  %w{clang
                    -fuse-ld=lld -static -fpic -flto=thin
                    -lc -lm -pthread -ldl -lexecinfo -lelf
                  }
                else
                  %w{clang
                    -fuse-ld=lld -rdynamic -static -fpic -flto=thin
                    -lc -pthread -ldl -latomic
                  }
                end

    link_args <<
      if ctx.options.release
        "-O3"
      else
        "-O0"
      end

    ctx.link_libraries.each do |x|
      link_args << "-l" + x
    end

    link_args << obj_filename
    link_args << "-o" << ctx.options.binary_name

    res = Process.run("/usr/bin/env", link_args, output: STDOUT, error: STDERR)
    raise "linker failed" unless res.exit_code == 0

    if ctx.options.release
      res = Process.run("/usr/bin/env", ["strip", ctx.options.binary_name], output: STDOUT, error: STDERR)
      raise "strip failed" unless res.exit_code == 0
    end
  ensure
    File.delete(obj_filename) if obj_filename
  end
end
