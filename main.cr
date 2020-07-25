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
      run do |opts, args|
        if opts.backtrace
          Cli.compile_backtrace
        else
          Cli.compile
        end
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
        run do |opts, args|
          if opts.backtrace
            Cli.eval_backtrace(args.code)
          else
            Cli.eval(args.code)
          end
        end
      end
      sub "run" do
        alias_name "r"
        desc "build and run code"
        usage "mare run [options]"
        help short: "-h"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        run do |opts, args|
          if opts.backtrace
            Cli.run_backtrace
          else
            Cli.run
          end
        end
      end
      sub "build" do
        alias_name "b"
        desc "build code"
        usage "mare build [options]"
        help short: "-h"
        option "-b", "--backtrace", desc: "Show backtrace on error", type: Bool, default: false
        run do |opts, args|
          if opts.backtrace
            Cli.compile_backtrace
          else
            Cli.compile
          end
        end
      end
    end

    def self.compile
      Mare::Compiler.compile(Dir.current, :binary)
      exit 0
    rescue e : Mare::Error
      STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
      exit 1
    end

    def self.compile_backtrace
      Mare::Compiler.compile(Dir.current, :binary)
      exit 0
    end

    def self.run
      exit Mare::Compiler.compile(Dir.current, :eval).eval.exitcode
    rescue e : Mare::Error
      STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
      exit 1
    end

    def self.run_backtrace
      exit Mare::Compiler.compile(Dir.current, :eval).eval.exitcode
    end

    def self.eval(code)
      exit Mare::Compiler.eval(code)
    rescue e : Mare::Error
      STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
      exit 1
    end

    def self.eval_backtrace(code)
      exit Mare::Compiler.eval(code)
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
