module Pegmatite
  # Pattern::Repeat is used to specify a pattern that can or must repeat
  # for a specified minimum number of occurrences.
  #
  # When the child pattern eventually fails to match, fail overall if the
  # minimum number of occurrences has not yet been met.
  # Otherwise, succeed overall, consuming all bytes from the occurences that
  # succeeded (not consuming any bytes from the final failing occurrence).
  # Like Pattern::Optional, this pattern will never fail if @min is zero.
  class Pattern::Repeat < Pattern
    def initialize(@child : Pattern, @min = 0)
    end
    
    def inspect(io)
      @child.inspect(io)
      io << ".repeat("
      @min.inspect(io)
      io << ")"
    end
    
    def dsl_name
      "repeat"
    end
    
    def description
      "#{@min} or more occurrences of #{@child.description}"
    end
    
    def _match(source, offset, state) : MatchResult
      total_length = 0
      tokens : Array(Token)? = nil
      
      # Keep trying to match the child pattern until we can't anymore.
      count = 0
      loop do
        length, result = @child.match(source, offset + total_length, state)
        
        # If the child pattern failed to match, either return early with the
        # failure or end the loop successfully, depending on whether we've
        # already met the specified minimum number of occurrences.
        if !result.is_a?(MatchOK)
          if count < @min
            state.observe_fail(offset + total_length + length, @child)
            return {total_length + length, result}
          else
            break
          end
        end
        
        # Add to our running total of consumed bytes.
        total_length += length
        
        # Capture the result if it is a token or array of tokens,
        # accounting for the case where the current tokens list is nil.
        if state.tokenize
          case result
          when Token
            if tokens.is_a?(Array(Token))
              tokens << result
            else
              tokens = [] of Token
              tokens << result
            end
          when Array(Token)
            if tokens.is_a?(Array(Token))
              tokens.concat result
            else
              tokens = result.dup
            end
          end
        end
        
        # Increase the occurrence counter and consider breaking early if we are
        # parsing zero-length patterns and we've already met our minimum
        count += 1
        break if (count > @min) && (length == 0)
      end
      
      {total_length, tokens}
    end
  end
end
