require "./src/mare"

# TODO: Use more sophisticated CLI parsing.
if ARGV == ["ls"]
  Mare::Server.new.run
else
  Mare::Compiler.compile(Dir.current, :binary)
end
