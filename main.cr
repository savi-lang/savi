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
      option "-o NAME", "--output=NAME", desc: "Name of the output binary"
      run do |opts, args|
        options = Mare::Compiler::CompilerOptions.new(
          release: opts.release,
          no_debug: opts.no_debug,
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
        run do |opts, args|
          options = Mare::Compiler::CompilerOptions.new(
            release: opts.release,
            no_debug: opts.no_debug,
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
        run do |opts, args|
          options = Mare::Compiler::CompilerOptions.new(
            release: opts.release,
            no_debug: opts.no_debug,
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
        run do |opts, args|
          options = Mare::Compiler::CompilerOptions.new(
            release: opts.release,
            no_debug: opts.no_debug,
          )
          if opts.output
            options.binary_name = opts.output.not_nil!
          end
          Cli.compile options, opts.backtrace
        end
      end
    end

    def self.compile(options, backtrace = false)
      if backtrace
        Mare::Compiler.compile(Dir.current, :binary, options)
        exit 0
      else
        begin
          Mare::Compiler.compile(Dir.current, :binary, options)
          exit 0
        rescue e
          STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
          exit 1
        end
      end
    end

    def self.run(options, backtrace = false)
      if backtrace
        exit Mare::Compiler.compile(Dir.current, :eval, options).eval.exitcode
      else
        begin
          exit Mare::Compiler.compile(Dir.current, :eval, options).eval.exitcode
        rescue e
          STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
          exit 1
        end
      end
    end

    def self.eval(code, options, backtrace = false)
      if backtrace
        exit Mare::Compiler.eval(code, options)
      else
        begin
          exit Mare::Compiler.eval(code, options)
        rescue e
          STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
          exit 1
        end
      end
    end
  end
end

Mare::Cli.start(ARGV)

# # TODO: Use more sophisticated CLI parsing.
# if ARGV == ["server"]
# elsif ARGV[0]? == "eval"
#   begin
#     exit Mare::Compiler.eval(ARGV[1])
#   rescue e : Mare::Error
#     STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
#     exit 1
#   end
# elsif ARGV[0]? == "run"
#   begin
#     exit Mare::Compiler.compile(Dir.current, :eval).eval.exitcode
#   rescue e : Mare::Error
#     STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
#     exit 1
#   end
# else
#   Mare::Compiler.compile(Dir.current, :binary)
# end
