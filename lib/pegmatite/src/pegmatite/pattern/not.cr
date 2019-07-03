module Pegmatite
  # Pattern::Not is used for negative-lookahead.
  #
  # Parsing will fail if the child pattern parsing succeeds.
  # Otherwise, the pattern succeeds, consuming zero bytes.
  # However, reaching the end of the file will always fail.
  #
  # Composing two Pattern::Not instances inside one another is a valid strategy
  # for positive lookahead. (TODO: test for this example)
  class Pattern::Not < Pattern
    def initialize(@child : Pattern)
    end
    
    def description
      "excluding #{@child.description}"
    end
    
    def match(source, offset, state) : MatchResult
      return {0, self} if offset >= source.size
      
      length, result = @child.match(source, offset, state)
      case result
      when MatchOK
        {length, self}
      else
        {0, nil}
      end
    end
  end
end
