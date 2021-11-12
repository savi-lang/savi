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

    # Use clang to orchestrate the linking process (clang will call the linker
    # for us with appropriate arguments based on the args we have given it).
    # For all platforms, we enable position-independent-code and
    # thin link time optimization as defaults.
    link_args = %w{clang -fpic -flto=thin}

    # We also use clang for optimizations, when compiling in release mode.
    link_args << (ctx.options.release ? "-O3" : "-O0")

    # Based on the target, choose which libraries to explicitly link.
    # On some platforms, some of the relevant libraries we need are implicit.
    target = Target.new(ctx.code_gen.target_machine.triple)
    link_args.concat(
      if target.linux?
        %w{-ldl -pthread -lc -lm -latomic}
      elsif target.freebsd?
        %w{-ldl -pthread -lc -lm -lexecinfo -lelf}
      elsif target.macos?
        %w{}
      else
        raise NotImplementedError.new(target)
      end
    )

    # Link any additional libraries requested by the user program.
    ctx.link_libraries.each do |x|
      link_args << "-l" + x
    end

    # Finally, specify the input object file and the output filename.
    link_args << obj_filename
    link_args << "-o" << ctx.options.binary_name

    res = Process.run("/usr/bin/env", link_args, output: STDOUT, error: STDERR)
    raise "linker failed" unless res.exit_code == 0

    if ctx.options.release
      res = Process.run("/usr/bin/env", ["strip", ctx.options.binary_name], output: STDOUT, error: STDERR)
      raise "strip failed" unless res.exit_code == 0
    end
  ensure
    File.delete(obj_filename) if obj_filename && File.exists?(obj_filename)
  end
end
