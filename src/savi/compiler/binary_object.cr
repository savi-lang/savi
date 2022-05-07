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
  DEFAULT_RUNTIME_PATH = File.expand_path(
    "../../lib/libsavi_runtime",
    Process.executable_path.not_nil!
  )

  def self.runtime_bc_path(target) : String
    path = File.join(
      DEFAULT_RUNTIME_PATH,
      "libsavi_runtime-#{runtime_bc_triple(target)}.bc"
    )

    raise "no runtime bitcode found at path: #{path}" unless File.exists?(path)

    path
  end

  def self.runtime_bc_triple(target) : String
    if target.linux?
      if target.musl?
        if target.x86_64?
          return "x86_64-unknown-linux-musl"
        elsif target.arm64?
          return "arm64-unknown-linux-musl"
        end
      else
        if target.x86_64?
          return "x86_64-unknown-linux-gnu"
        end
      end
    elsif target.freebsd?
      if target.x86_64?
        return "x86_64-unknown-freebsd"
      end
    elsif target.macos?
      if target.x86_64?
        return "x86_64-apple-macosx"
      elsif target.arm64?
        return "arm64-apple-macosx"
      end
    elsif target.windows?
      if target.x86_64? && target.msvc?
        return "x86_64-unknown-windows-msvc"
      end
    end

    raise NotImplementedError.new(target.inspect)
  end

  def self.run(ctx)
    llvm = ctx.code_gen.llvm
    machine = ctx.code_gen.target_machine
    target = Target.new(machine.triple)
    mod = ctx.code_gen.mod

    # Obtain the Savi runtime as an LLVM module from the right bitcode on disk.
    runtime_bc = LLVM::MemoryBuffer.from_file(runtime_bc_path(target))
    runtime = llvm.parse_bitcode(runtime_bc).as(LLVM::Module)

    # Remap the directory in debug info to point to the bundled runtime source.
    LibLLVM.remap_di_directory_for_savi(runtime,
      "libsavi_runtime",
      File.join(BinaryObject::DEFAULT_RUNTIME_PATH, "src")
    )

    # Link the runtime bitcode module into the generated application module.
    LibLLVM.link_modules(mod.to_unsafe, runtime.to_unsafe)

    # Now run LLVM passes, doing full optimization if in release mode.
    # Otherwise we will only run a minimal set of passes.
    LibLLVM.optimize_for_savi(mod.to_unsafe, ctx.options.release)

    # Emit the combined/optimized LLVM IR to a file if requested to do so.
    mod.print_to_file("#{Binary.path_for(ctx)}.ll") if ctx.options.llvm_ir

    # Write the program to disk as a binary object file.
    obj_path = "#{ctx.manifests.root.not_nil!.bin_path}.o"
    FileUtils.mkdir_p(File.dirname(obj_path))
    machine.emit_obj_to_file(mod, obj_path)

    obj_path
  end
end
