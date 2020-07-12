require "./src/mare"

# TODO: Use more sophisticated CLI parsing.
if ARGV == ["server"]
  Mare::Server.new.run
elsif ARGV[0]? == "eval"
  begin
    exit Mare::Compiler.eval(ARGV[1])
  rescue e : Mare::Error
    STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
    exit 1
  end
elsif ARGV[0]? == "run"
  begin
    exit Mare::Compiler.compile(Dir.current, :eval).eval.exitcode
  rescue e : Mare::Error
    STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
    exit 1
  end
else
  begin
    Mare::Compiler.compile(Dir.current, :binary)
  rescue e : Mare::Error
    STDERR.puts "Compilation Error:\n\n#{e.message}\n\n"
    exit 1
  end
end
