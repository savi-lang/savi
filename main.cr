require "./src/mare"

# TODO: Use more sophisticated CLI parsing.
if ARGV == ["server"]
  Mare::Server.new.run
else
  Mare::Compiler.compile(Dir.current, :binary)
end
