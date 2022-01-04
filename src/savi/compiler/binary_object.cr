require "file"
require "file_utils"
require "llvm"

##
# The purpose of the BinaryObject pass is to produce a binary object of the
# program, ready to be linked to create a binary executable.
#
# This pass would usually only be used for troubleshooting or cross-compiling.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps temporary state (on the stack) at the program level.
# This pass produces no output state (aside from the side effect below).
# !! This pass has the side-effect of writing files to disk.
#
class Savi::Compiler::BinaryObject
  DEFAULT_RUNTIME_PATH = File.expand_path("../../lib", Process.executable_path.not_nil!)

  RUNTIME_BC_PATH = ENV.fetch("SAVI_RUNTIME_BC_PATH", [
    DEFAULT_RUNTIME_PATH,
    "/usr/lib",
    "/usr/local/lib",
  ].join(":"))

  def self.find_runtime_bc(searchpath) : String?
    searchpath.split(":", remove_empty: true)
      .map { |path| File.join(path, "libsavi_runtime.bc") }
      .find { |path| File.exists?(path) }
  end

  def self.run(ctx)
    llvm = ctx.code_gen.llvm
    machine = ctx.code_gen.target_machine
    mod = ctx.code_gen.mod

    # Obtain the Savi runtime as an LLVM module from bitcode somewhere on disk.
    runtime_bc_path = find_runtime_bc(RUNTIME_BC_PATH) \
      || raise "libsavi_runtime.bc not found"
    runtime_bc = LLVM::MemoryBuffer.from_file(runtime_bc_path)
    runtime = llvm.parse_bitcode(runtime_bc).as(LLVM::Module)

    # Remap the directory in debug info to point to the bundled runtime source.
    LibLLVM.remap_di_directory_for_savi(runtime,
      "libsavi_runtime",
      File.join(BinaryObject::DEFAULT_RUNTIME_PATH, "libsavi_runtime")
    )

    # Link the runtime bitcode module into the generated application module.
    LibLLVM.link_modules(mod.to_unsafe, runtime.to_unsafe)

    # Now run LLVM passes, doing full optimization if in release mode.
    # Otherwise we will only run a minimal set of passes.
    LibLLVM.optimize_for_savi(mod.to_unsafe, ctx.options.release)

    # Write the program to disk as a binary object file.
    obj_path = "#{ctx.manifests.root.not_nil!.bin_path}.o"
    FileUtils.mkdir_p(File.dirname(obj_path))
    machine.emit_obj_to_file(mod, obj_path)

    obj_path
  end
end
