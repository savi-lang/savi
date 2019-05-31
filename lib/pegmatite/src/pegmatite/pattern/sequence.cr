module Pegmatite
  # Pattern::Sequence is used to specify a consecutive sequence of patterns.
  #
  # Parsing will fail if any child pattern fails, returning that failure result.
  # Otherwise, succeeds and consumes all bytes from all child patterns.
  class Pattern::Sequence < Pattern
    def initialize(@children = [] of Pattern)
    end
    
    # Override this DSL operator to accrue into the existing sequence.
    def >>(other); Pattern::Sequence.new(@children.dup.push(other)) end
    
    def description
      case @children.size
      when 0 then "(empty sequence!)"
      when 1 then @children[0].description
      when 2 then "first #{@children.map(&.description).join(" then ")}"
      else        "first #{@children[0...-1].map(&.description).join(", ")}" \
                  " then #{@children[-1].description}"
      end
    end
    
    def match(source, offset, state) : MatchResult
      total_length = 0
      tokens : Array(Token)? = nil
      
      # Match each child pattern, capturing tokens and increasing total_length.
      @children.each do |child|
        length, result = child.match(source, offset + total_length, state)
        total_length += length
        
        # Fail as soon as one child pattern fails.
        if !result.is_a?(MatchOK)
          state.observe_fail(offset + total_length, child)
          return {total_length, result}
        end
        
        # Capture the result if it is a token or array of tokens,
        # accounting for the case where the current tokens list is nil.
        if state.tokenize
          case result
          when Token
            if tokens.is_a?(Array(Token))
              tokens << result
            else
              tokens = [result]
            end
          when Array(Token)
            if tokens.is_a?(Array(Token))
              tokens.concat result
            else
              tokens = result
            end
          end
        end
      end
      
      {total_length, tokens}
    end
  end
end
