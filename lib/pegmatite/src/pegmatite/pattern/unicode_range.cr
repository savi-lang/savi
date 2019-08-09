module Pegmatite
  # Pattern::UnicodeRange is used to consume a single character from within
  # a specified contiguous range of acceptable codepoints.
  #
  # Parsing will fail if a valid UTF-32 codepoint couldn't be parsed,
  # or if the parsed codepoint didn't fall in the specified range.
  # Otherwise, the pattern succeeds, consuming the matched bytes.
  class Pattern::UnicodeRange < Pattern
    def initialize(@min : UInt32, @max : UInt32)
    end
    
    def inspect(io)
      io << "range("
      @min.chr.inspect(io)
      io << ", "
      @max.chr.inspect(io)
      io << ")"
    end
    
    def dsl_name
      "range"
    end
    
    def description
      "#{@min.chr.inspect}..#{@max.chr.inspect}"
    end
    
    def _match(source, offset, state) : MatchResult
      c, length = Pattern::UnicodeAny.utf32_at(source, offset)
      
      # Fail if a valid UTF-32 character couldn't be parsed.
      return {0, self} if c == 0xFFFD_u32
      
      # Fail if the character wasn't in the expected range.
      return {0, self} if (c < @min) || (c > @max)
      
      # Otherwise, pass.
      {length, nil}
    end
  end
end
