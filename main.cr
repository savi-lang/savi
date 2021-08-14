require "./src/savi"

require "clim"

module Savi
  class Cli < Clim
    main do
      desc "Savi compiler."
      usage "savi [sub_command]. Default sub_command in build"
      version "savi version: 0.0.1", short: "-v"
      help short: "-h"
      option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
      option "-r", "--release", desc: "Compile in release mode", type: Bool, default: false
      option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
      option "--print-ir", desc: "Print generated LLVM IR", type: Bool, default: false
      option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
      option "-o NAME", "--output=NAME", desc: "Name of the output binary"
      option "-p NAME", "--pass=NAME", desc: "Name of the compiler pass to target"
      run do |opts, args|
        options = Savi::Compiler::CompilerOptions.new(
          release: opts.release,
          no_debug: opts.no_debug,
          print_ir: opts.print_ir,
          print_perf: opts.print_perf,
        )
        options.binary_name = opts.output.not_nil! if opts.output
        options.target_pass = Savi::Compiler.pass_symbol(opts.pass) if opts.pass
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
        run do |opts, args|
          options = Savi::Compiler::CompilerOptions.new(
            release: opts.release,
            no_debug: opts.no_debug,
            print_ir: opts.print_ir,
            print_perf: opts.print_perf,
          )
          Cli.eval args.code, options, opts.backtrace
        end
      end
      sub "run" do
        alias_name "r"
        desc "build and run code"
        usage "savi run [options]"
        help short: "-h"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        option "-r", "--release", desc: "Compile in release mode", type: Bool, default: false
        option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
        option "--print-ir", desc: "Print generated LLVM IR", type: Bool, default: false
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        option "-p NAME", "--pass=NAME", desc: "Name of the compiler pass to target"
        run do |opts, args|
          options = Savi::Compiler::CompilerOptions.new(
            release: opts.release,
            no_debug: opts.no_debug,
            print_ir: opts.print_ir,
            print_perf: opts.print_perf,
          )
          options.target_pass = Savi::Compiler.pass_symbol(opts.pass) if opts.pass
          Cli.run options, opts.backtrace
        end
      end
      sub "build" do
        alias_name "b"
        desc "build code"
        usage "savi build [options]"
        help short: "-h"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        option "-r", "--release", desc: "Compile in release mode", type: Bool, default: false
        option "-o NAME", "--output=NAME", desc: "Name of the output binary"
        option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
        option "--print-ir", desc: "Print generated LLVM IR", type: Bool, default: false
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        run do |opts, args|
          options = Savi::Compiler::CompilerOptions.new(
            release: opts.release,
            no_debug: opts.no_debug,
            print_ir: opts.print_ir,
            print_perf: opts.print_perf,
          )
          if opts.output
            options.binary_name = opts.output.not_nil!
          end
          Cli.compile options, opts.backtrace
        end
      end
      sub "compilerspec" do
        desc "run compiler specs"
        usage "savi compilerspec [target] [options]"
        help short: "-h"
        argument "target", type: String, required: true, desc: "savi.spec.md file to run"
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        run do |opts, args|
          options = Savi::Compiler::CompilerOptions.new(
            print_perf: opts.print_perf,
          )
          Cli.compilerspec args.target, options
        end
      end
      sub "format" do
        desc "Format savi files in the current directory and all subdirectories"
        usage "savi format [options]"
        help short: "-h"
        option "-c", "--check", desc: "Check for formatting issues without overwriting files", type: Bool, default: false
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        run do |opts, args|
          Cli.format(check_only: opts.check, backtrace: opts.backtrace)
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
            "Savi compiler error occured with message \"#{e.message}\". Consider submitting new issue."
          else
            "Unknown Savi compiler error occured. Consider submitting new issue."
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

    def self.compilerspec(target, options)
      _add_backtrace true do
        spec = Savi::SpecMarkdown.new(target)
        result =
          case spec.target_pass
          when :format
            Savi::SpecMarkdown::Format.new(spec).verify!
          else
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

        if check_only
          sources.group_by(&.library).each { |source_library, sources|
            ctx = Savi.compiler.compile(sources, :import)
            AST::Format.check(ctx, ctx.root_library_link, ctx.root_docs)
            errors.concat(ctx.errors)
          }
          puts "Checked #{sources.size} files."
        else
          edited_count = 0
          sources.group_by(&.library).each { |source_library, sources|
            ctx = Savi.compiler.compile(sources, :import)
            edits_by_doc =
              AST::Format.run(ctx, ctx.root_library_link, ctx.root_docs)

            edits_by_doc.each { |doc, edits|
              source = doc.pos.source
              puts "Fixing #{source.path}"
              edited = AST::Format.apply_edits(source.entire_pos, edits)[0].source
              File.write(source.path, edited.content)
              edited_count += 1
            }

            errors.concat(ctx.errors)
          }
          puts "Fixed #{edited_count} of #{sources.size} files."
        end

        errors.any? ? finish_with_errors(errors, backtrace) : 0
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
      puts
      1 # exit code reflects the fact that compilation errors occurred
    end
  end
end

Savi::Cli.start(ARGV)
