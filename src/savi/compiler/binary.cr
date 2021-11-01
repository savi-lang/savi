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
  RUNTIME_BC_PATH = ENV.fetch("SAVI_RUNTIME_BC_PATH", [
    File.expand_path("../../lib", Process.executable_path.not_nil!),
    "/usr/lib",
    "/usr/local/lib",
  ].join(":"))

  def self.run(ctx)
    new.run(ctx)
  end

  def find_runtime_bc(searchpath) : String?
    searchpath.split(":", remove_empty: true)
      .map { |path| File.join(path, "libsavi_runtime.bc") }
      .find { |path| File.exists?(path) }
  end

  def run(ctx)
    llvm = ctx.code_gen.llvm
    machine = ctx.code_gen.target_machine
    mod = ctx.code_gen.mod

    target = Target.new(machine.triple)
    ponyrt_bc_path = find_runtime_bc(RUNTIME_BC_PATH) || raise "libsavi_runtime.bc not found"

    ponyrt_bc = LLVM::MemoryBuffer.from_file(ponyrt_bc_path)
    ponyrt = llvm.parse_bitcode(ponyrt_bc).as(LLVM::Module)

    # Link the pony runtime bitcode into the generated module.
    LibLLVM.link_modules(mod.to_unsafe, ponyrt.to_unsafe)

    bin_filename = File.tempname(".savi.user.program")
    obj_filename = "#{bin_filename}.o"

    machine.emit_obj_to_file(mod, obj_filename)

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
