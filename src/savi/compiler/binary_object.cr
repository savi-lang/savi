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
    elsif target.dragonfly?
      if target.x86_64?
        return "x86_64-unknown-dragonfly"
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
    runtime.target = ctx.code_gen.target_machine.triple

    # Remap the directory in debug info to point to the bundled runtime source.
    LibLLVM.remap_di_directory_for_savi(runtime,
      "libsavi_runtime",
      File.join(BinaryObject::DEFAULT_RUNTIME_PATH, "src")
    )

    # If we're configured to remove assertions in the runtime, remove them now.
    #
    # This is the default when compiling in release mode, but can be overridden
    # if the user wants to keep assertions even in release mode.
    #
    # Removing assertions means less overhead, but undefined behavior when the
    # assert is false, rather than predictably crashing with a helpful message.
    if !ctx.options.runtime_asserts
      mark_runtime_asserts_as_unreachable(runtime)
    end

    # Compile any C/C++ code files that we use and link those as well.
    ctx.link_c_files.each { |c_file_path|
      c_module = invoke_clang_compiler(ctx, target, "c", c_file_path)
      LibLLVM.link_modules(mod.to_unsafe, c_module.to_unsafe)
    }
    ctx.link_cpp_files.each { |cpp_file_path|
      cpp_module = invoke_clang_compiler(ctx, target, "c++", cpp_file_path)
      LibLLVM.link_modules(mod.to_unsafe, cpp_module.to_unsafe)
    }

    # Link the runtime bitcode module into the generated application module.
    LibLLVM.link_modules(mod.to_unsafe, runtime.to_unsafe)

    # We're not compiling a library, so we want to mark as many functions
    # as possible with private linkage, so LLVM can optimize them aggressively,
    # including inlining them, eliminating them if they are not used, and/or
    # marking them to use the fastest available calling convention.
    #
    # Prior to this step, the public runtime functions are all marked as
    # external, so they would miss out on optimizations if we don't do this.
    mark_module_functions_as_private(mod)

    # Now run LLVM passes, doing full optimization if in release mode.
    # Otherwise we will only run a minimal set of passes.
    unless ctx.options.llvm_optimize_nothing
      LibLLVM.optimize_for_savi(mod.to_unsafe, ctx.options.release)
    end

    # Now that we've optimized, only actually called functions remain,
    # so we can mark for linking those libraries that are associated to
    # specific functions that come from those libraries.
    ctx.link_libraries_by_foreign_function.each { |ffi_name, lib_name|
      next unless mod.functions[ffi_name]?
      next if ctx.link_libraries[lib_name]?
      ctx.link_libraries[lib_name] = :dynamic
    }

    # Strip debug info from the module if requested.
    LibLLVM.strip_module_debug_info(mod.to_unsafe) if ctx.options.no_debug

    # Emit the combined/optimized LLVM IR to a file if requested to do so.
    FileUtils.mkdir_p(File.dirname(Binary.path_for(ctx)))
    mod.print_to_file("#{Binary.path_for(ctx)}.ll") if ctx.options.llvm_ir

    # Write the program to disk as a binary object file.
    obj_path = "#{ctx.manifests.root.not_nil!.bin_path}.o"
    FileUtils.mkdir_p(File.dirname(obj_path))
    machine.emit_obj_to_file(mod, obj_path)

    obj_path
  end

  def self.mark_runtime_asserts_as_unreachable(mod : LLVM::Module)
    # Find the function that is called upon assertion failure.
    func = mod.functions["ponyint_assert_fail"]

    # Remove all the code inside it.
    basic_blocks = [] of LLVM::BasicBlock
    func.basic_blocks.each { |b| basic_blocks << b }
    basic_blocks.each(&.delete)

    # Build a new entry block that simply says the code is unreachable.
    builder = mod.context.new_builder
    builder.position_at_end(func.basic_blocks.append("entry"))
    builder.unreachable

    # Instruct LLVM to always inline this function, effectively replacing
    # all call sites of it with the `unreachable` instruction (or, more
    # typically, get rid of the branch altogether and place an `llvm.assume`
    # intrinsic on the condition, instructing LLVM to optimize it away).
    func.add_attribute(LLVM::Attribute::AlwaysInline)
  end

  def self.mark_module_functions_as_private(mod : LLVM::Module)
    mod.functions.each { |func|
      # Only consider functions whose linkage is currently external or internal,
      # avoiding functions with the more specific kinds of linkage that
      # probably shouldn't be meddled with, such as LinkOnceODR on Windows.
      next unless func.linkage == LLVM::Linkage::External \
        || func.linkage == LLVM::Linkage::Internal

      # Only consider functions that are non-empty of code. In other words,
      # only consider defined functions rather than merely declared ones.
      next if func.basic_blocks.empty?

      # We can't make the program entrypoint private - it must be external
      # so it can be linked to the standard startup code by the linker.
      next if func.name == "main"

      # Set linkage to private - we don't need this to be externally visible.
      func.linkage = LLVM::Linkage::Private

      # Also set the DLL Storage Class to default, which is necessary
      # on Windows targets because if we have functions with `private`
      # linkage, they must not have `dllexport` or `dllimport` specified.
      func.dll_storage_class = LLVM::DLLStorageClass::Default

      # Remove "noinline", "optnone", and "uwtable" attributes if present.
      # These often are assigned by clang alongside external linkage,
      # so we want to remove them when setting to private linkage.
      func.remove_attribute(LLVM::Attribute::NoInline)
      func.remove_attribute(LLVM::Attribute::OptimizeNone)
      func.remove_attribute(LLVM::Attribute::UWTable)
    }
  end

  def self.get_default_clang_flags(ctx, language)
    LibLLVM.default_clang_flags_for_savi(
      ctx.code_gen.target_machine.triple, language,
      out out_args_ptr, out out_args_count
    )

    out_args = [] of String
    return out_args if out_args_ptr.null?

    out_args_count.times { |i|
      out_args << String.new(out_args_ptr[i]).dup
      LibC.free(out_args_ptr[i])
    }

    LibC.free(out_args_ptr)

    out_args
  end

  def self.each_sysroot_include_path(ctx, target)
    Binary.new.each_sysroot_lib_path(ctx, ctx.code_gen.target_info) { |lib_path|
      include_path = File.join(lib_path, "include")
      yield include_path if Dir.exists?(include_path)

      include_path = File.join(lib_path, "../include")
      yield include_path if Dir.exists?(include_path)

      include_path = File.join(lib_path, "../../include")
      yield include_path if Dir.exists?(include_path)

      substituted_include_path = lib_path.gsub(/\blib(64)?\b/, "include")
      if Dir.exists?(substituted_include_path)

        Dir.glob(File.join(substituted_include_path, "c++/*")) { |include_path|
          yield include_path if Dir.exists?(include_path)
        }

        yield substituted_include_path
      end

      if target.macos?
        include_path = File.join(lib_path, "../../System/Library/Frameworks/Kernel.framework/Headers")
        yield include_path if Dir.exists?(include_path)
      end
    }
  end

  def self.invoke_clang_compiler(ctx, target, language, c_file_path) : LLVM::Module
    compile_args = get_default_clang_flags(ctx, language)
    compile_args << "-triple" << ctx.code_gen.target_machine.triple
    each_sysroot_include_path(ctx, target) { |include_path|
      compile_args << "-I" << include_path
    }
    compile_args << "-fgnuc-version=4.2.1" if target.macos?
    compile_args << c_file_path

    is_debug = !ctx.options.no_debug

    llvm_module = LibLLVM.compile_clang_for_savi(
      ctx.code_gen.llvm,
      is_debug,
      compile_args.size, compile_args.map(&.to_unsafe),
      out out_ptr, out out_size,
    )

    # Print the output errors/warnings/info, if any.
    if out_size > 0
      output = String.new(out_ptr, out_size)

      output_lines = output.split("\n").reject(&.empty?)

      output_lines.each { |line| STDERR.puts(line) }
    end

    # Ensure the output data pointer, which was a fresh allocation, is freed.
    LibC.free(out_ptr)

    raise "failed to compile #{language} code" if llvm_module.null?

    c_module = LLVM::Module.new(llvm_module, ctx.code_gen.llvm)
    c_module.target = ctx.code_gen.target_machine.triple
    c_module
  end
end
