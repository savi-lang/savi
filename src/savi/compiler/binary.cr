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
  def self.path_for(ctx)
    ctx.manifests.root.not_nil!.bin_path
  end

  def self.run(ctx)
    new.run(ctx)
  end

  def run(ctx)
    target = ctx.code_gen.target_info
    bin_path = Binary.path_for(ctx)
    bin_path += ".exe" if target.windows?

    # Compile a temporary binary object file, that we will remove after we
    # use it in the linker invocation to create the final binary.
    obj_path = BinaryObject.run(ctx)

    # Use a linker to turn make an executable binary from the object file.
    # We use an embedded lld linker, passing link arguments of our own crafting,
    # based on information about the target platform and finding system paths.
    if target.linux? || target.freebsd? || target.dragonfly?
      link_for_linux_or_bsd(ctx, target, obj_path, bin_path)
    elsif target.macos?
      link_for_macosx(ctx, target, obj_path, bin_path)
    elsif target.windows?
      link_for_windows(ctx, target, obj_path, bin_path)
    else
      raise NotImplementedError.new(target.inspect)
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
    lib_paths = [] of String
    link_args = %w{ld64.lld -execute}

    # Specify the target architecture.
    link_args << "-arch" << (target.arm64? ? "arm64" : "x86_64")

    # Use no_pie where available, for performance reasons.
    link_args << "-no_pie" unless target.arm64?

    # Set up explicitly requested library paths.
    each_explicit_lib_path(ctx) { |lib_path|
      lib_paths << lib_path
      link_args << "-L#{lib_path}"
    }

    # Set up the main library paths.
    each_sysroot_lib_path(ctx, target) { |lib_path|
      lib_paths << lib_path
      link_args << "-L#{lib_path}"
    }

    # Link the main system libraries.
    link_args << "-lSystem"

    # Target the earliest version of the OS SDK supported for this arch.
    # We don't expect the user program to use any bleeding-edge Apple features.
    # TODO: Support overriding this via the `MACOSX_DEPLOYMENT_TARGET` env var.
    sdk_version = (target.arm64? ? "11.0.0" : "10.9.0")
    link_args << "-platform_version" << "macos" << sdk_version << sdk_version

    # Link the C++ runtime if needed.
    link_args << "-lc++" if ctx.link_cpp_files.any?

    # Link any additional libraries indicated by user code.
    ctx.link_libraries.each { |name, kind| add_unix_lib(link_args, lib_paths, name, kind) }

    # Finally, specify the input object file and the output filename.
    link_args << obj_path
    link_args << "-o" << bin_path

    # Invoke the linker, using the MachO flavor.
    invoke_linker("mach_o", link_args)
  end

  # Link a EXE executable for a Windows target.
  def link_for_windows(ctx, target, obj_path, bin_path)
    lib_paths = [] of String
    link_args = %w{lld-link -nologo -defaultlib:libcmt -defaultlib:oldnames}

    # Set up explicitly requested library paths.
    each_explicit_lib_path(ctx) { |lib_path|
      lib_paths << lib_path
      link_args << "-libpath:#{lib_path}"
    }

    # Set up the main library paths.
    each_sysroot_lib_path(ctx, target) { |lib_path|
      lib_paths << lib_path
      link_args << "-libpath:#{lib_path}"
    }

    # Specify the base set of libraries to link to.
    add_windows_lib(link_args, lib_paths, "libcmt")  # C runtime startup - always needed
    add_windows_lib(link_args, lib_paths, "DbgHelp") # used by runtime platform/ponyassert.c
    add_windows_lib(link_args, lib_paths, "WS2_32")  # used by runtime lang/socket.c

    # Link any additional libraries indicated by user code.
    ctx.link_libraries.each { |name, kind| add_windows_lib(link_args, lib_paths, name) }

    # Finally, specify the input object file and the output filename.
    link_args << obj_path
    link_args << "-out:#{bin_path}"

    # Invoke the linker, using the COFF flavor.
    invoke_linker("coff", link_args)
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

    # Get the list of lib search paths.
    lib_paths = [] of String
    each_explicit_lib_path(ctx) { |lib_path| lib_paths << lib_path }
    each_sysroot_lib_path(ctx, target) { |path| lib_paths << path }
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
    link_args << "-lgcc"
    link_args << "-lgcc_s" unless target.dragonfly?

    link_args << "-lc" << "-ldl" << "-lpthread" << "-lm"
    link_args << "-latomic" unless target.freebsd? || target.dragonfly?
    link_args << "-lexecinfo" if target.freebsd? || target.dragonfly?

    # Link the C++ runtime if needed.
    if ctx.link_cpp_files.any?
      if target.freebsd? || target.dragonfly?
        link_args << "-lc++"
      else
        link_args << "-lstdc++"
      end
    end

    # Link any additional libraries indicated by user code.
    ctx.link_libraries.each { |name, kind| add_unix_lib(link_args, lib_paths, name, kind) }

    # Finally, specify the input object file and the output filename.
    link_args << obj_path
    link_args << "-o" << bin_path

    # Invoke the linker, using the ELF flavor.
    invoke_linker("elf", link_args)
  end

  private def add_unix_lib(link_args, lib_paths, name, kind)
    if kind == :prefer_static
      found_lib = maybe_find_in_paths(lib_paths, "lib#{name}.a")
      if found_lib
        link_args << found_lib
        return
      end
    end

    link_args << "-l#{name}"
  end

  private def add_windows_lib(link_args, lib_paths, name)
    if lib_paths.any? { |lib_path|
      File.exists?(File.join(lib_path, "#{name}.Lib"))
    }
      link_args << "-defaultlib:#{name}.Lib"
    elsif lib_paths.any? { |lib_path|
      File.exists?(File.join(lib_path, "#{name}.lib"))
    }
      link_args << "-defaultlib:#{name}.lib"
    else
      link_args << "-defaultlib:#{name.downcase}.lib"
    end
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

    if target.dragonfly?
      return "/libexec/ld-elf.so.2"
    end

    raise NotImplementedError.new(target.inspect)
  end

  def each_explicit_lib_path(ctx)
    if ENV["LIBRARY_PATH"]? && !ENV["LIBRARY_PATH"].empty?
      ENV["LIBRARY_PATH"].split(":").each { |l| yield l }
    end
  end

  # Yield each sysroot-based path in which to search for linkable libs/objs.
  def each_sysroot_lib_path(ctx, target)
    sys_roots =
      if ENV["SAVI_SYS_ROOT"]? && !ENV["SAVI_SYS_ROOT"].empty?
        [ENV["SAVI_SYS_ROOT"]]
      elsif ENV["SDK_ROOT"]? && !ENV["SDK_ROOT"].empty?
        # TODO: Remove deprecated SDK_ROOT synonym.
        [ENV["SDK_ROOT"]]
      else
        if target.macos?
          ["/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"]
        elsif target.windows?
          [
            "/mnt/c/Program Files/Microsoft Visual Studio",
            "/mnt/c/Program Files (x86)/Windows Kits",
          ]
        else
          ["/"]
        end
      end

    yielded_any = false
    each_sysroot_lib_glob(ctx, target) { |lib_glob, check_suffix|
      sys_roots.each { |sys_root|
        Dir.glob(File.join(sys_root, lib_glob)) { |lib_path|
          # TODO: Remove this hack when we can go back to using globs for this,
          # after this Crystal bug with Dir.glob has been fixed and released:
          # - https://github.com/crystal-lang/crystal/issues/12056
          if check_suffix
            next unless lib_path.ends_with?(check_suffix)
          end

          next unless Dir.exists?(lib_path)

          yield lib_path
          yielded_any = true
        }
      }
    }

    raise "couldn't find any valid sysroot lib paths" unless yielded_any
  end

  # Yield each sysroot-based glob used to find paths that exist.
  def each_sysroot_lib_glob(ctx, target)
    # Handle MacOS sysroot paths.
    if target.macos?
      yield "/opt/homebrew/lib", nil
      yield "/usr/local/lib", nil
      yield "/usr/lib", nil
      return
    end

    # Handle Windows sysroot paths.
    if target.windows?
      yield "/**/x64", "um/x64"             # MSVC style
      yield "/**/x64", "ucrt/x64"           # MSVC style
      yield "/**/x64", "lib/x64"            # MSVC style
      yield "/**/x86_64", "lib/um/x86_64"   # xwin style
      yield "/**/x86_64", "lib/ucrt/x86_64" # xwin style
      yield "/**/x86_64", "lib/x86_64"      # xwin style
      return
    end

    if target.linux?
      if target.musl?
        if target.x86_64?
          # TODO: Support non-alpine musl variants?
          yield "/usr/lib/gcc/x86_64-alpine-linux-musl/*", nil
        elsif target.arm64?
          # TODO: Support non-alpine musl variants?
          yield "/usr/lib/gcc/aarch64-alpine-linux-musl/*", nil
        else
          raise NotImplementedError.new(target.inspect)
        end
      else
        if target.x86_64?
          yield "/lib/gcc/x86_64-linux-gnu/*", nil
          yield "/lib/gcc/x86_64-pc-linux-gnu/*", nil
          yield "/lib/x86_64-linux-gnu", nil
          yield "/usr/lib/gcc/x86_64-linux-gnu/*", nil
          yield "/usr/lib/gcc/x86_64-pc-linux-gnu/*", nil
          yield "/usr/lib/gcc-cross/x86_64-linux-gnu/*", nil
          yield "/usr/lib/x86_64-linux-gnu", nil
          yield "/usr/lib/gcc/x86_64-redhat-linux/*", nil
          yield "/usr/x86_64-linux-gnu/lib", nil
        else
          raise NotImplementedError.new(target.inspect)
        end
      end
    end

    yield "/lib64", nil
    yield "/usr/lib64", nil
    yield "/lib", nil
    yield "/usr/lib", nil
    yield "/usr/local/lib", nil

    if target.dragonfly?
      yield "/usr/lib/gcc80", nil
    end
  end

  # Given a prioritized list of search paths and a file name, find the file.
  # Raises an error if the file couldn't be found in any of the paths
  def find_in_paths(paths, file_name) : String
    result = maybe_find_in_paths(paths, file_name)
    raise "failed to find #{file_name}" if !result
    result
  end
  def maybe_find_in_paths(paths, file_name) : String?
    paths.each { |path|
      file_path = File.join(path, file_name)
      return file_path if File.exists?(file_path)
    }
    nil
  end

  def invoke_linker(flavor, link_args)
    link_res = LibLLVM.link_for_savi(
      flavor,
      link_args.size, link_args.map(&.to_unsafe),
      out out_ptr, out out_size,
    )

    # Print the output errors/warnings/info, if any.
    if out_size > 0
      output = String.new(out_ptr, out_size)

      # Filter the output to remove unnecessary warnings we don't want to see.
      output_lines = output.split("\n").reject(&.empty?)
        # MacOS likes to warn if you make your apps compatible with older
        # versions of their SDK, even though this is explicitly supported,
        # as long as your application isn't relying on new features of the SDK.
        # We expect this warning to always be present, because we deliberately
        # specify the oldest supported version, so we don't want to see it.
        .reject(&.matches?(/which is newer than target minimum/))

      output_lines.each { |line| STDERR.puts(line) }
    end

    # Ensure the output data pointer, which was a fresh allocation, is freed.
    LibC.free(out_ptr)

    raise "failed to link" unless link_res
  end
end
