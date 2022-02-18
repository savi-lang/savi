module Pegmatite
  # Pattern::DynamicPop is used pop a dynamic match off the stack after matching,
  # such as to mark the end of a dynamic delimiter.
  #
  # If the child pattern produces tokens, those tokens will be passed as-is.
  #
  # Returns the result of the child pattern's parsing.
  class Pattern::DynamicPop < Pattern
    def initialize(@child : Pattern, @label : Symbol)
    end

    def inspect(io)
      io << "dynamic_pop(\""
      @label.inspect(io)
      io << "\")"
    end

    def dsl_name
      "dynamic_pop"
    end

    def description
      @label.inspect
    end

    def _match(source, offset, state) : MatchResult
      length, result = @child.match(source, offset, state)
      return {length, result} if !result.is_a?(MatchOK)

      last_delim = state.dynamic_matches.last

      val = source[offset...(offset + length)]

      if last_delim[0] != @label || last_delim[1] != val
        state.observe_fail(offset + length, @child)
        return {length, result}
      end

      state.dynamic_matches.pop

      {length, result}
    end
  end
end
