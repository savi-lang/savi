module Pegmatite
  # Pattern::EOF specifies that the end of the source must follow
  # after the child pattern has been parsed successfully.
  #
  # If the child pattern doesn't match, its result is returned.
  # Fails if the cursor hasn't reached the end of the source.
  # Otherwise, the result of the child pattern is returned.
  class Pattern::EOF < Pattern
    def initialize(@child : Pattern)
    end
    
    def description
      "#{@child.description} followed by end-of-file"
    end
    
    def match(source, offset, state) : MatchResult
      length, result = @child.match(source, offset, state)
      return {length, result} if !result.is_a?(MatchOK)
      
      # Fail if the end of the source hasn't been reached yet.
      if (offset + length) != source.bytesize
        state.observe_fail(offset + length + 1, @child)
        return {0, self}
      end
      
      {length, result}
    end
  end
end
