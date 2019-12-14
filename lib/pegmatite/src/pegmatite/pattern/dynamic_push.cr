module Pegmatite
  # Pattern::DynamicPush is used to dynamically push a dynamic match onto the stack,
  # usually for the purposes of dynamically constraining the scope of a pattern.
  #
  # If the child pattern produces tokens, those tokens will be passed as-is.
  #
  # Returns the result of the child pattern's parsing.
  class Pattern::DynamicPush < Pattern
    def initialize(@child : Pattern, @label : Symbol)
    end

    def inspect(io)
      io << "dynamic_push(\""
      @label.inspect(io)
      io << "\")"
    end

    def dsl_name
      "dynamic_push"
    end

    def description
      @label.inspect
    end

    def _match(source, offset, state) : MatchResult
      length, result = @child.match(source, offset, state)
      return {length, result} if !result.is_a?(MatchOK)

      val = source[offset...(offset+length)]

      state.dynamic_matches.push({@label, val})

      {length, result}
    end
  end
end
