require "./src/savi"

require "clim"

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
      option "-r", "--release", desc: "Compile in release mode", type: Bool, default: false
      option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
      option "--print-ir", desc: "Print generated LLVM IR", type: Bool, default: false
      option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
      option "-C", "--cd=DIR", desc: "Change the working directory"
      option "-p NAME", "--pass=NAME", desc: "Name of the compiler pass to target"
      run do |opts, args|
        options = Savi::Compiler::Options.new(
          release: opts.release,
          no_debug: opts.no_debug,
          print_ir: opts.print_ir,
          print_perf: opts.print_perf,
        )
        options.target_pass = Savi::Compiler.pass_symbol(opts.pass) if opts.pass
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
        option "-r", "--release", desc: "Compile in release mode", type: Bool, default: false
        option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
        option "--print-ir", desc: "Print generated LLVM IR", type: Bool, default: false
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        option "-C", "--cd=DIR", desc: "Change the working directory"
        run do |opts, args|
          options = Savi::Compiler::Options.new(
            release: opts.release,
            no_debug: opts.no_debug,
            print_ir: opts.print_ir,
            print_perf: opts.print_perf,
          )
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
        option "-r", "--release", desc: "Compile in release mode", type: Bool, default: false
        option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
        option "--print-ir", desc: "Print generated LLVM IR", type: Bool, default: false
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        option "-C", "--cd=DIR", desc: "Change the working directory"
        option "-p NAME", "--pass=NAME", desc: "Name of the compiler pass to target"
        run do |opts, args|
          options = Savi::Compiler::Options.new(
            release: opts.release,
            no_debug: opts.no_debug,
            print_ir: opts.print_ir,
            print_perf: opts.print_perf,
          )
          options.target_pass = Savi::Compiler.pass_symbol(opts.pass) if opts.pass
          options.manifest_name = args.name.not_nil! if args.name
          Dir.cd(opts.cd.not_nil!) if opts.cd
          Cli.run options, opts.backtrace
        end
      end
      sub "build" do
        alias_name "b"
        desc "build code"
        usage "savi build [name] [options]"
        help short: "-h"
        argument "name", type: String, required: false, desc: "Name of the manifest to compile"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        option "-r", "--release", desc: "Compile in release mode", type: Bool, default: false
        option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
        option "--print-ir", desc: "Print generated LLVM IR", type: Bool, default: false
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        option "-C", "--cd=DIR", desc: "Change the working directory"
        run do |opts, args|
          options = Savi::Compiler::Options.new(
            release: opts.release,
            no_debug: opts.no_debug,
            print_ir: opts.print_ir,
            print_perf: opts.print_perf,
          )
          options.manifest_name = args.name.not_nil! if args.name
          Dir.cd(opts.cd.not_nil!) if opts.cd
          Cli.compile options, opts.backtrace
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
        run do |opts, args|
          Dir.cd(opts.cd.not_nil!) if opts.cd
          Cli.ffigen(header: args.header, backtrace: opts.backtrace)
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
        ctx = Savi.compiler.compile(Dir.current, options.target_pass || :eval, options)
        ctx.errors.any? ? finish_with_errors(ctx.errors, backtrace) : ctx.eval.exitcode
      end
    end

    def self.eval(code, options, backtrace = false)
      _add_backtrace backtrace do
        ctx = Savi.compiler.eval(code, options)
        ctx.errors.any? ? finish_with_errors(ctx.errors, backtrace) : ctx.eval.exitcode
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
              edited = AST::Format.apply_edits(source.entire_pos, edits)[0].source
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

    def self.ffigen(header : String, backtrace : Bool)
      _add_backtrace backtrace do
        gen = Savi::FFIGen.new(header)
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
