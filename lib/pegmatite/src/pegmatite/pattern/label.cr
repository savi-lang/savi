module Pegmatite
  # Pattern::Label is used to provide a symbolic name for a pattern,
  # usually for the purposes of producing a token that marks the range of bytes
  # that was matched by the child pattern, though if @tokenize is set to false,
  # then no token will be produced and the name is used only for description,
  # which is useful for making clearer error messages when the match fails.
  #
  # If the child pattern also produces tokens, those tokens will appear
  # after the token that was created by this Pattern::Label, and these can be
  # distinguished in the token stream by the fact that all such tokens will
  # have offset ranges that are sub-ranges of the offset range of the prior.
  #
  # Returns the result of the child pattern's parsing, possibly preceded with
  # a new token whose symbol is the symbolic name assigned to this pattern.
  class Pattern::Label < Pattern
    def initialize(@child : Pattern, @label : Symbol, @tokenize = true)
    end
    
    def description
      @label.inspect
    end
    
    def match(source, offset, state) : MatchResult
      length, result = @child.match(source, offset, state)
      
      # If requested, this label will be added as a token to the token stream,
      # preceding any other tokens emitted by the child pattern.
      # This won't happen if the child pattern failed to parse.
      if state.tokenize && @tokenize
        new_token = {@label, offset, offset + length}
        
        case result
        when Nil
          result = new_token
        when Token
          result = [new_token, result]
        when Array(Token)
          result = [new_token].concat(result)
        end
      end
      
      {length, result}
    end
  end
end
