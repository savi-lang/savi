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
  RUNTIME_BC_PATH = ENV.fetch("SAVI_RUNTIME_BC_PATH", [
    File.expand_path("../../lib", Process.executable_path.not_nil!),
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
    target = Target.new(machine.triple)

    # Load the runtime from a bitcode.
    runtime_bc_path = find_runtime_bc(RUNTIME_BC_PATH) \
      || raise "libsavi_runtime.bc not found"
    runtime_bc = LLVM::MemoryBuffer.from_file(runtime_bc_path)
    runtime = llvm.parse_bitcode(runtime_bc).as(LLVM::Module)

    # Link the pony runtime bitcode into the generated module.
    LibLLVM.link_modules(mod.to_unsafe, runtime.to_unsafe)

    # Maybe optimize the generated LLVM code.
    optimize(mod) if ctx.options.release

    # Emit as a binary object file.
    obj_path = "#{ctx.manifests.root.not_nil!.bin_path}.o"
    FileUtils.mkdir_p(File.dirname(obj_path))
    machine.emit_obj_to_file(mod, obj_path)

    obj_path
  end

  private def self.optimize(mod)
    # pp :OPTIMIZING

    # puts
    # puts
    # puts
    # puts
    # puts
    # puts
    # mod.dump

    pass_registry = LLVM::PassRegistry.instance
    pass_registry.initialize_all

    pass_manager_builder = LLVM::PassManagerBuilder.new.tap { |b|
      b.opt_level = 3
      b.size_level = 0
      b.use_inliner_with_threshold = 275
    }

    fun_pass_manager = mod.new_function_pass_manager.tap { |m|
      pass_manager_builder.populate(m)
    }

    mod_pass_manager = LLVM::ModulePassManager.new.tap { |m|
      pass_manager_builder.populate(m)
    }

    fun_pass_manager.run mod
    mod_pass_manager.run mod

    # puts
    # puts
    # puts
    # puts
    # puts
    # puts
    # mod.dump
    # puts
    # puts
    # puts
    # puts
    # puts
    # puts
    # puts

    # pp :OPTIMIZING_DONE
  end
end
