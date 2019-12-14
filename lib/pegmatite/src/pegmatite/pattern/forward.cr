module Pegmatite
  # Pattern::Forward is used to create a forward declaration,
  # such as when defining a pattern that will be used recursively with another.
  #
  # There is no child pattern present at declaration, so one must be added
  # later by calling define exactly once before the pattern is used to parse.
  #
  # Returns the result of the child pattern's parsing.
  class Pattern::Forward < Pattern
    @child : Pattern?

    def inspect(io)
      io << "forward"
    end

    def dsl_name
      "forward"
    end

    def initialize
      @child = nil
    end

    def define(child)
      raise "already defined" unless @child.nil?
      @child = child
    end

    def description
      @child.as(Pattern).description
    end

    def _match(source, offset, state) : MatchResult
      @child.as(Pattern).match(source, offset, state)
    end
  end
end
