require "./src/mare"

# TODO: Use more sophisticated CLI parsing.
if ARGV == ["server"]
  Mare::Server.new.run
elsif ARGV[0]? == "eval"
  exit Mare::Compiler.eval(ARGV[1])
else
  Mare::Compiler.compile(Dir.current, :binary)
end
