require "./src/savi"

require "random"
require "file_utils"
require "clim"
require "fswatch"

module Savi
  class Cli < Clim
    main do
      desc "Savi compiler."
      usage "savi [sub_command]. Default sub_command in build"
      version [
        "savi version: #{Savi::VERSION}",
        "llvm version: #{Savi::LLVM_VERSION}",
      ].join("\n"), short: "-v"
      help short: "-h"
      option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
      option "-r", "--release", desc: "Compile in release mode (i.e. with optimizations)", type: Bool, default: false
      option "--fix", desc: "Auto-fix compile errors where possible", type: Bool, default: false
      option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
      option "--with-runtime-asserts", desc: "Compile with runtime assertions even in release mode", type: Bool, default: false
      option "--llvm-ir", desc: "Write generated LLVM IR to a file", type: Bool, default: false
      option "--llvm-keep-fns", desc: "Don't allow LLVM to remove functions from the output", type: Bool, default: false
      option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
      option "-X", "--cross-compile=TRIPLE", desc: "Cross compile to the given target triple"
      option "-C", "--cd=DIR", desc: "Change the working directory"
      option "-p NAME", "--pass=NAME", desc: "Name of the compiler pass to target"
      run do |opts, args|
        options = Savi::Compiler::Options.new(
          release: opts.release,
          no_debug: opts.no_debug,
          print_perf: opts.print_perf,
        )
        options.runtime_asserts = opts.with_runtime_asserts || !opts.release
        options.llvm_ir = true if opts.llvm_ir
        options.llvm_keep_fns = true if opts.llvm_keep_fns
        options.auto_fix = true if opts.fix
        options.target_pass = Savi::Compiler.pass_symbol(opts.pass) if opts.pass
        options.cross_compile = opts.cross_compile.not_nil! if opts.cross_compile
        Dir.cd(opts.cd.not_nil!) if opts.cd
        Cli.compile options, opts.backtrace
      end
      sub "server" do
        alias_name "s"
        desc "run lsp server"
        usage "savi server [options]"
        help short: "-h"
        run do |opts, args|
          Savi::Server.new.run
        end
      end
      sub "eval" do
        alias_name "e"
        desc "evaluate code"
        usage "savi eval [code] [options]"
        help short: "-h"
        argument "code", type: String, required: true, desc: "code to evaluate"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        option "-r", "--release", desc: "Compile in release mode (i.e. with optimizations)", type: Bool, default: false
        option "--fix", desc: "Auto-fix compile errors where possible", type: Bool, default: false
        option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
        option "--with-runtime-asserts", desc: "Compile with runtime assertions even in release mode", type: Bool, default: false
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        option "-C", "--cd=DIR", desc: "Change the working directory"
        run do |opts, args|
          options = Savi::Compiler::Options.new(
            release: opts.release,
            no_debug: opts.no_debug,
            print_perf: opts.print_perf,
          )
          options.runtime_asserts = opts.with_runtime_asserts || !opts.release
          options.auto_fix = true if opts.fix
          Dir.cd(opts.cd.not_nil!) if opts.cd
          Cli.eval args.code, options, opts.backtrace
        end
      end
      sub "run" do
        alias_name "r"
        desc "build and run code"
        usage "savi run [name] [options]"
        help short: "-h"
        argument "name", type: String, required: false, desc: "Name of the manifest to compile"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        option "-r", "--release", desc: "Compile in release mode (i.e. with optimizations)", type: Bool, default: false
        option "--fix", desc: "Auto-fix compile errors where possible", type: Bool, default: false
        option "--watch", desc: "Run continuously, watching for file changes (EXPERIMENTAL)", type: Bool, default: false
        option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
        option "--with-runtime-asserts", desc: "Compile with runtime assertions even in release mode", type: Bool, default: false
        option "--llvm-ir", desc: "Write generated LLVM IR to a file", type: Bool, default: false
        option "--llvm-keep-fns", desc: "Don't allow LLVM to remove functions from the output", type: Bool, default: false
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        option "-X", "--cross-compile=TRIPLE", desc: "Cross compile to the given target triple"
        option "-C", "--cd=DIR", desc: "Change the working directory"
        option "-p NAME", "--pass=NAME", desc: "Name of the compiler pass to target"
        run do |opts, args|
          options = Savi::Compiler::Options.new(
            release: opts.release,
            no_debug: opts.no_debug,
            print_perf: opts.print_perf,
          )
          options.runtime_asserts = opts.with_runtime_asserts || !opts.release
          options.llvm_ir = true if opts.llvm_ir
          options.llvm_keep_fns = true if opts.llvm_keep_fns
          options.auto_fix = true if opts.fix
          options.target_pass = Savi::Compiler.pass_symbol(opts.pass) if opts.pass
          options.cross_compile = opts.cross_compile.not_nil! if opts.cross_compile
          options.manifest_name = args.name.not_nil! if args.name
          Dir.cd(opts.cd.not_nil!) if opts.cd
          if opts.watch
            Cli.run_with_watch(options, opts.backtrace)
          else
            Cli.run(options, opts.backtrace)
          end
        end
      end
      sub "build" do
        alias_name "b"
        desc "build code"
        usage "savi build [name] [options]"
        help short: "-h"
        argument "name", type: String, required: false, desc: "Name of the manifest to compile"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        option "-r", "--release", desc: "Compile in release mode (i.e. with optimizations)", type: Bool, default: false
        option "--fix", desc: "Auto-fix compile errors where possible", type: Bool, default: false
        option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
        option "--with-runtime-asserts", desc: "Compile with runtime assertions even in release mode", type: Bool, default: false
        option "--llvm-ir", desc: "Write generated LLVM IR to a file", type: Bool, default: false
        option "--llvm-keep-fns", desc: "Don't allow LLVM to remove functions from the output", type: Bool, default: false
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        option "-X", "--cross-compile=TRIPLE", desc: "Cross compile to the given target triple"
        option "-C", "--cd=DIR", desc: "Change the working directory"
        run do |opts, args|
          options = Savi::Compiler::Options.new(
            release: opts.release,
            no_debug: opts.no_debug,
            print_perf: opts.print_perf,
          )
          options.runtime_asserts = opts.with_runtime_asserts || !opts.release
          options.llvm_ir = true if opts.llvm_ir
          options.llvm_keep_fns = true if opts.llvm_keep_fns
          options.auto_fix = true if opts.fix
          options.manifest_name = args.name.not_nil! if args.name
          options.cross_compile = opts.cross_compile.not_nil! if opts.cross_compile
          Dir.cd(opts.cd.not_nil!) if opts.cd
          Cli.compile options, opts.backtrace
        end
      end
      sub "init" do
        run do
          # TODO: How can we avoid defining this `run` block?
          # And how can we prevent the no-op action that happens if the user
          # runs this partial command instead of a full/proper command?
        end
        sub "lib" do
          desc "initialize a new library project in the current directory"
          usage "savi init lib NAME"
          help short: "-h"
          argument "name", type: String, required: true, desc: "Name of the library manifest to create"
          option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
          option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
          option "-C", "--cd=DIR", desc: "Change the working directory"
          run do |opts, args|
            if opts.cd
              FileUtils.mkdir_p(opts.cd.not_nil!)
              Dir.cd(opts.cd.not_nil!)
            end
            exit 1 unless Savi::Init::Lib.run(args.name)

            # Now also run `savi deps update --for spec` to fetch dependencies.
            options = Savi::Compiler::Options.new
            options.manifest_name = "spec"
            options.print_perf = true if opts.print_perf
            options.deps_update = "" # mark all dependencies for update
            options.target_pass = :load # stop after the :load pass is done
            options.auto_fix = true # auto-fix changes due to updated deps
            Cli.compile options, opts.backtrace
          end
        end
        sub "bin" do
          desc "initialize a new executable binary project in the current directory"
          usage "savi init bin NAME"
          help short: "-h"
          argument "name", type: String, required: true, desc: "Name of the binary manifest to create"
          option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
          option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
          option "-C", "--cd=DIR", desc: "Change the working directory"
          run do |opts, args|
            if opts.cd
              FileUtils.mkdir_p(opts.cd.not_nil!)
              Dir.cd(opts.cd.not_nil!)
            end
            exit 1 unless Savi::Init::Bin.run(args.name)
          end
        end
      end
      sub "deps" do
        run do
          # TODO: How can we avoid defining this `run` block?
          # And how can we prevent the no-op action that happens if the user
          # runs this partial command instead of a full/proper command?
        end
        sub "update" do
          desc "update dependencies"
          usage "savi deps update [name] [options]"
          help short: "-h"
          argument "name", type: String, required: false, desc: "Name of the dependency to update"
          option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
          option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
          option "-C", "--cd=DIR", desc: "Change the working directory"
          option "--for=MANIFEST", desc: "Specify the manifest to update dependencies for"
          run do |opts, args|
            options = Savi::Compiler::Options.new
            options.print_perf = true if opts.print_perf
            options.manifest_name = opts.for.not_nil! if opts.for
            options.deps_update = args.name || "" # mark all or one dependency for update
            options.target_pass = :load # stop after the :load pass is done
            options.auto_fix = true # auto-fix changes due to updated deps
            Dir.cd(opts.cd.not_nil!) if opts.cd
            Cli.compile options, opts.backtrace
          end
        end
        sub "add" do
          desc "add a dependency"
          usage "savi deps add NAME [options]"
          help short: "-h"
          argument "name", type: String, required: true, desc: "Name of the dependency to add"
          option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
          option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
          option "-C", "--cd=DIR", desc: "Change the working directory"
          option "--for=MANIFEST", desc: "Specify the manifest to add the dependency to"
          option "--from=LOCATION", desc: "Specify the location to fetch the dependency from"
          run do |opts, args|
            options = Savi::Compiler::Options.new
            options.print_perf = true if opts.print_perf
            options.manifest_name = opts.for.not_nil! if opts.for
            options.deps_update = args.name
            options.deps_add = args.name
            options.deps_add_location = opts.from.not_nil! if opts.from
            options.target_pass = :load # stop after the :load pass is done
            options.auto_fix = true # auto-fix changes due to updated deps
            Dir.cd(opts.cd.not_nil!) if opts.cd
            Cli.compile options, opts.backtrace
          end
        end
      end
      sub "compilerspec" do
        desc "run compiler specs"
        usage "savi compilerspec [file] [options]"
        help short: "-h"
        argument "file", type: String, required: true, desc: "savi.spec.md file to run"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: true
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        option "-C", "--cd=DIR", desc: "Change the working directory"
        run do |opts, args|
          options = Savi::Compiler::Options.new(
            print_perf: opts.print_perf,
          )
          Dir.cd(opts.cd.not_nil!) if opts.cd
          Cli.compilerspec(args.file, options, backtrace: opts.backtrace)
        end
      end
      sub "format" do
        desc "Format savi files in the current directory and all subdirectories"
        usage "savi format [options]"
        help short: "-h"
        option "-c", "--check", desc: "Check for formatting issues without overwriting files", type: Bool, default: false
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        option "-C", "--cd=DIR", desc: "Change the working directory"
        run do |opts, args|
          Dir.cd(opts.cd.not_nil!) if opts.cd
          Cli.format(check_only: opts.check, backtrace: opts.backtrace)
        end
      end
      sub "ffigen" do
        desc "Generate savi code with FFI bindings for the given header file"
        usage "savi ffigen [header]"
        help short: "-h"
        argument "header", type: String, required: true, desc: "header file to parse"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        option "-C", "--cd=DIR", desc: "Change the working directory"
        option "-I", "--include-dir=DIR", desc: "Add an include file search path", type: Array(String)
        run do |opts, args|
          Dir.cd(opts.cd.not_nil!) if opts.cd
          options = Savi::FFIGen::Options.new
          options.header_name = args.header
          options.include_dirs = opts.include_dir
          Cli.ffigen(options, backtrace: opts.backtrace)
        end
      end
    end

    def self._add_backtrace(backtrace = false)
      if backtrace
        exit yield
      else
        begin
          exit yield
        rescue e : Error | Pegmatite::Pattern::MatchError
          STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
          exit 1
        rescue e
          message = if e.message
            "Savi compiler error occured with message \"#{e.message}\". Consider submitting an issue ticket."
          else
            "Unknown Savi compiler error occured. Consider submitting an issue ticket."
          end
          STDERR.puts message
          exit 1
        end
      end
    end

    def self.compile(options, backtrace = false)
      _add_backtrace backtrace do
        ctx = Savi.compiler.compile(Dir.current, options.target_pass || :binary, options)
        ctx.errors.any? ? finish_with_errors(ctx.errors, backtrace) : 0
      end
    end

    def self.run(options, backtrace = false)
      _add_backtrace backtrace do
        ctx = Savi.compiler.compile(Dir.current, options.target_pass || :run, options)
        ctx.errors.any? ? finish_with_errors(ctx.errors, backtrace) : ctx.run.exitcode
      end
    end

    # This feature is experimental - it's currently not quite working,
    # due to some issues with inaccurate or incomplete caching of passes.
    # Also, it doesn't watch precisely the right set of files -
    # ideally it would watch all of the package globs that are in use,
    # as well as the manifest files where those packages are defined.
    # Once we get those issues ironed out, we should mark it as being
    # no longer experimental, and publicize it as a recommended way of working.
    def self.run_with_watch(options, backtrace = false)
      ctx = Savi.compiler.compile(Dir.current, options.target_pass || :run, options)
      finish_with_errors(ctx.errors, backtrace) if ctx.errors.any?
      last_compiled_at = Time.utc

      FSWatch.watch(".", latency: 0.25, recursive: true) do |event|
        next unless event.created? || event.updated? || event.removed? || event.renamed?
        next if event.timestamp < last_compiled_at

        ctx = Savi.compiler.compile(Dir.current, options.target_pass || :run, options)
        finish_with_errors(ctx.errors, backtrace) if ctx.errors.any?
        last_compiled_at = Time.utc
      end

      sleep
    end

    def self.eval(code, options, backtrace = false)
      _add_backtrace backtrace do
        dirname = "/tmp/savi-eval-#{Random::Secure.hex}"
        Dir.mkdir_p(dirname)
        Savi.compiler.source_service.set_source_override(
          "#{dirname}/manifest.savi",
          ":manifest eval\n:sources \"src/main.savi\""
        )
        Savi.compiler.source_service.set_source_override(
          "#{dirname}/src/main.savi",
          ":actor Main\n:new (env)\n#{code}"
        )
        ctx = Savi.compiler.compile(dirname, :run, options)
        ctx.errors.any? ? finish_with_errors(ctx.errors, backtrace) : ctx.run.exitcode
      end
    end

    def self.compilerspec(target, options, backtrace)
      _add_backtrace backtrace do
        spec = Savi::SpecMarkdown.new(target)
        result =
          case spec.target_pass
          when :format
            Savi::SpecMarkdown::Format.new(spec).verify!
          else
            options.skip_manifest = true
            ctx = Savi.compiler.compile(spec.sources, spec.target_pass, options)
            spec.verify!(ctx)
          end

        result ? 0 : 1
      end
    end

    def self.format(
      check_only : Bool,
      backtrace : Bool
    )
      _add_backtrace backtrace do
        errors = [] of Error
        sources = Savi.compiler.source_service.get_recursive_sources(Dir.current)
        options = Savi::Compiler::Options.new
        options.skip_manifest = true

        if check_only
          sources.each { |source_package, sources|
            ctx = Savi.compiler.compile(sources, :manifests, options)
            AST::Format.check(ctx, ctx.root_package_link, ctx.root_docs)
            errors.concat(ctx.errors)
          }
          puts "Checked #{sources.size} files."
        else
          edited_count = 0
          sources.each { |source_package, sources|
            ctx = Savi.compiler.compile(sources, :manifests, options)
            edits_by_doc =
              AST::Format.run(ctx, ctx.root_package_link, ctx.root_docs)

            edits_by_doc.each { |doc, edits|
              source = doc.pos.source
              puts "Fixing #{source.path}"
              edited = source.entire_pos
                .apply_edits(edits.map { |edit| {edit.pos, edit.replacement} })[0].source
              Savi.compiler.source_service
                .overwrite_source_at(source.path, edited.content)
              edited_count += 1
            }

            errors.concat(ctx.errors)
          }
          puts "Fixed #{edited_count} of #{sources.size} files."
        end

        errors.any? ? finish_with_errors(errors, backtrace) : 0
      end
    end

    def self.ffigen(options : Savi::FFIGen::Options, backtrace : Bool)
      _add_backtrace backtrace do
        gen = Savi::FFIGen.new(options)
        puts String.build { |io| gen.emit(io) }

        0
      end
    end

    def self.finish_with_errors(errors, backtrace = false) : Int32
      puts
      puts "Compilation Error#{errors.size > 1 ? "s" : ""}:"
      errors.each { |error|
        puts
        puts "---"
        puts
        puts error.message(backtrace)
      }
      1 # exit code reflects the fact that compilation errors occurred
    end
  end
end

Savi::Cli.start(ARGV)
