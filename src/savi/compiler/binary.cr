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
    target = Target.new(ctx.code_gen.target_machine.triple)
    bin_path = ctx.manifests.root.not_nil!.bin_path

    # Compile a temporary binary object file, that we will remove after we
    # use it in the linker invocation to create the final binary.
    obj_path = BinaryObject.run(ctx)

    # Use a linker to turn make an executable binary from the object file.
    # We use an embedded lld linker, passing link arguments of our own crafting,
    # based on information about the target platform and finding system paths.
    if target.linux? || target.freebsd?
      link_for_linux_or_bsd(ctx, target, obj_path, bin_path)
    elsif target.macos?
      link_for_macosx(ctx, target, obj_path, bin_path)
    else
      raise NotImplementedError.new(target.inspect)
    end

    # If requested, strip debugging symbols from the binary.
    if ctx.options.no_debug && !target.macos?
      res = Process.run("/usr/bin/env", ["strip", bin_path], output: STDOUT, error: STDERR)
      raise "strip failed" unless res.exit_code == 0
    end

    # MacOS has a different way of dealing with debugging symbols - they are
    # in a subdirectory whose name matches the binary but is suffixed with .dSYM
    # rather than being embedded in the binary itself, as on other platforms.
    if target.macos?
      res = Process.run("/usr/bin/env", ["rm", "-rf", "#{bin_path}.dSYM"], output: STDOUT, error: STDERR)
      raise "remove old dSYM failed" unless res.exit_code == 0

      unless ctx.options.no_debug
        res = Process.run("/usr/bin/env", ["dsymutil", bin_path], output: STDOUT, error: STDERR)
        raise "dsymutil failed" unless res.exit_code == 0
      end
    end
  ensure
    # Remove the temporary object file to clean up after ourselves a bit.
    File.delete(obj_path) if obj_path && File.exists?(obj_path)
  end

  # Link a MachO executable for a MacOSX target.
  def link_for_macosx(ctx, target, obj_path, bin_path)
    link_args = %w{ld64.lld -execute}

    # Specify the target architecture.
    link_args << "-arch" << (target.arm64? ? "arm64" : "x86_64")

    # Use no_pie where available, for performance reasons.
    link_args << "-no_pie" unless target.arm64?

    # Set up the main library paths.
    # TODO: Support overriding (supplementing?) this via the `SDK_ROOT` env var.
    each_sysroot_lib_path(target) { |lib_path| link_args << "-L#{lib_path}" }

    # Link the main system libraries.
    link_args << "-lSystem"

    # Target the earliest version of the OS SDK supported for this arch.
    # We don't expect the user program to use any bleeding-edge Apple features.
    # TODO: Support overriding this via the `MACOSX_DEPLOYMENT_TARGET` env var.
    sdk_version = (target.arm64? ? "11.0.0" : "10.9.0")
    link_args << "-platform_version" << "macos" << sdk_version << sdk_version

    # Finally, specify the input object file and the output filename.
    link_args << "-o" << bin_path
    link_args << obj_path

    # Invoke the linker, using the MachO flavor.
    link_res = LibLLVM.link_for_savi_directly(
      "mach_o",
      link_args.size, link_args.map(&.to_unsafe)
    )
    raise "failed to link" unless link_res
  end

  # Link an ELF executable for a Linux or FreeBSD target.
  def link_for_linux_or_bsd(ctx, target, obj_path, bin_path)
    link_args = %w{ld.lld}

    # Add various "extra flags" based on the target platform.
    link_args << "-z" << "now" if target.musl?
    link_args << "-z" << "relro" if target.linux?
    link_args << "--hash-style=both"
    link_args << "--eh-frame-hdr"

    # Specify the target architecture, in the terms the linker will understand.
    if target.x86_64?
      link_args << "-m" << "elf_x86_64"
    elsif target.arm64?
      link_args << "-m" << "aarch64linux"
    else
      raise NotImplementedError.new(target.inspect)
    end

    # Specify the dynamic linker library, based on the target platform.
    link_args << "-dynamic-linker" << dynamic_linker_for_linux_or_bsd(target)

    # Get the list of lib search paths within the sysroot.
    lib_paths = [] of String
    each_sysroot_lib_path(target) { |path| lib_paths << path }
    lib_paths.each { |lib_path| link_args << "-L#{lib_path}" }

    # Also find the mandatory ceremony objects that all programs need to link.
    link_args << find_in_paths(lib_paths, "crt1.o")
    link_args << find_in_paths(lib_paths, "crti.o")
    link_args << find_in_paths(lib_paths, "crtbegin.o")
    link_args << find_in_paths(lib_paths, "crtend.o")
    link_args << find_in_paths(lib_paths, "crtn.o")

    # Enable link-time-optimization with "thin" LTO.
    link_args << "-plugin-opt=mcpu=#{target.arm64? ? "aarch64" : "x86-64"}"
    link_args << "-plugin-opt=#{ctx.options.release ? "O3" : "O0"}"
    link_args << "-plugin-opt=thinlto"

    # TODO: Allow option to build with "-static" for linux-musl target

    # Link the libraries that we always need.
    link_args << "-lgcc" << "-lgcc_s"
    link_args << "-lc" << "-ldl" << "-lpthread" << "-latomic" << "-lm"
    link_args << "-lexecinfo" if target.musl? || target.freebsd?

    # Finally, specify the input object file and the output filename.
    link_args << "-o" << bin_path
    link_args << obj_path

    # Invoke the linker, using the ELF flavor.
    link_res = LibLLVM.link_for_savi_directly(
      "elf",
      link_args.size, link_args.map(&.to_unsafe)
    )
    raise "failed to link" unless link_res
  end

  # Get the path to the dynamic linker library for a Linux or FreeBSD target.
  def dynamic_linker_for_linux_or_bsd(target) : String
    if target.linux?
      if target.musl?
        if target.x86_64?
          return "/lib/ld-musl-x86_64.so.1"
        elsif target.arm64?
          return "/lib/ld-musl-aarch64.so.1"
        end
      end

      if target.x86_64?
        return "/lib64/ld-linux-x86-64.so.2"
      end
    end

    if target.freebsd?
      return "/libexec/ld-elf.so.1"
    end

    raise NotImplementedError.new(target.inspect)
  end

  # Yield each sysroot-based path in which to search for linkable libs/objs.
  def each_sysroot_lib_path(target)
    sysroot = "/" # TODO: Allow user to supply custom sysroot for cross-compile.

    yielded_any = false
    each_sysroot_lib_glob(target) { |lib_glob|
      Dir.glob(lib_glob) { |lib_path|
        next unless Dir.exists?(lib_path)

        yield lib_path
        yielded_any = true
      }
    }

    raise "couldn't find any valid sysroot lib paths" unless yielded_any
  end

  # Yield each sysroot-based glob used to find paths that exist.
  def each_sysroot_lib_glob(target)
    # For MacOS, we have just one valid sysroot path, so we can finish early.
    if target.macos?
      yield "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib"
      return
    end

    if target.linux?
      if target.musl?
        if target.x86_64?
          # TODO: Support non-alpine musl variants?
          yield "/usr/lib/gcc/x86_64-alpine-linux-musl/*"
        elsif target.arm64?
          # TODO: Support non-alpine musl variants?
          yield "/usr/lib/gcc/aarch64-alpine-linux-musl/*"
        else
          raise NotImplementedError.new(target.inspect)
        end
      else
        if target.x86_64?
          yield "/lib/gcc/x86_64-linux-gnu/*"
          yield "/lib/x86_64-linux-gnu"
          yield "/usr/lib/gcc/x86_64-linux-gnu/*"
          yield "/usr/lib/x86_64-linux-gnu"
        else
          raise NotImplementedError.new(target.inspect)
        end
      end
    end

    yield "/lib64"
    yield "/usr/lib64"
    yield "/lib"
    yield "/usr/lib"
  end

  # Given a prioritized list of search paths and a file name, find the file.
  # Raises an error if the file couldn't be found in any of the paths
  def find_in_paths(paths, file_name) : String
    paths.each { |path|
      file_path = File.join(path, file_name)
      return file_path if File.exists?(file_path)
    }

    raise "failed to find #{file_name}"
  end
end
