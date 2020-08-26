require "./src/mare"

require "clim"

module Mare
  class Cli < Clim
    main do
      desc "Mare compiler."
      usage "mare [sub_command]. Default sub_command in build"
      version "mare version: 0.0.1", short: "-v"
      help short: "-h"
      option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
      option "-r", "--release", desc: "Compile in release mode", type: Bool, default: false
      option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
      option "--print-ir", desc: "Print generated LLVM IR", type: Bool, default: false
      option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
      option "-o NAME", "--output=NAME", desc: "Name of the output binary"
      run do |opts, args|
        options = Mare::Compiler::CompilerOptions.new(
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
      sub "server" do
        alias_name "s"
        desc "run lsp server"
        usage "mare server [options]"
        help short: "-h"
        run do |opts, args|
          Mare::Server.new.run
        end
      end
      sub "eval" do
        alias_name "e"
        desc "evaluate code"
        usage "mare eval [code] [options]"
        help short: "-h"
        argument "code", type: String, required: true, desc: "code to evaluate"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        option "-r", "--release", desc: "Compile in release mode", type: Bool, default: false
        option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
        option "--print-ir", desc: "Print generated LLVM IR", type: Bool, default: false
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        run do |opts, args|
          options = Mare::Compiler::CompilerOptions.new(
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
        usage "mare run [options]"
        help short: "-h"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        option "-r", "--release", desc: "Compile in release mode", type: Bool, default: false
        option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
        option "--print-ir", desc: "Print generated LLVM IR", type: Bool, default: false
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        run do |opts, args|
          options = Mare::Compiler::CompilerOptions.new(
            release: opts.release,
            no_debug: opts.no_debug,
            print_ir: opts.print_ir,
            print_perf: opts.print_perf,
          )
          Cli.run options, opts.backtrace
        end
      end
      sub "build" do
        alias_name "b"
        desc "build code"
        usage "mare build [options]"
        help short: "-h"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        option "-r", "--release", desc: "Compile in release mode", type: Bool, default: false
        option "-o NAME", "--output=NAME", desc: "Name of the output binary"
        option "--no-debug", desc: "Compile without debug info", type: Bool, default: false
        option "--print-ir", desc: "Print generated LLVM IR", type: Bool, default: false
        option "--print-perf", desc: "Print compiler performance info", type: Bool, default: false
        run do |opts, args|
          options = Mare::Compiler::CompilerOptions.new(
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
    end

    def self._add_backtrace(backtrace = false)
      if backtrace
        exit yield
      else
        begin
          yield
          exit 0
        rescue e : Error | Pegmatite::Pattern::MatchError
          STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
          exit 1
        rescue e
          message = if e.message
            "Mare compiler error occured with message \"#{e.message}\". Consider submitting new issue."
          else
            "Unknown Mare compiler error occured. Consider submitting new issue."
          end
          STDERR.puts message
          exit 1
        end
      end
    end

    def self.compile(options, backtrace = false)
      _add_backtrace backtrace do
        Mare.compiler.compile(Dir.current, :binary, options)
        0
      end
    end

    def self.run(options, backtrace = false)
      _add_backtrace backtrace do
        Mare.compiler.compile(Dir.current, :eval, options).eval.exitcode
      end
    end

    def self.eval(code, options, backtrace = false)
      _add_backtrace backtrace do
        Mare.compiler.eval(code, options)
      end
    end
  end
end

Mare::Cli.start(ARGV)
