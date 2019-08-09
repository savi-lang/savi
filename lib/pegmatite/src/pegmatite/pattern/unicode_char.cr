module Pegmatite
  # Pattern::UnicodeChar is used to consume a single specific character.
  #
  # Parsing will fail if a valid UTF-32 codepoint couldn't be parsed,
  # or if the parsed codepoint didn't match the expected one.
  # Otherwise, the pattern succeeds, consuming the matched bytes.
  class Pattern::UnicodeChar < Pattern
    def initialize(@expected : UInt32)
      raise "0xFFFD isn't a valid expected character" if @expected == 0xFFFD_u32
    end
    
    def inspect(io)
      io << "char("
      @expected.chr.inspect(io)
      io << ")"
    end
    
    def dsl_name
      "char"
    end
    
    def description
      @expected.chr.inspect
    end
    
    def _match(source, offset, state) : MatchResult
      c, length = Pattern::UnicodeAny.utf32_at(source, offset)
      
      # Fail if the character wasn't the expected value.
      return {0, self} if c != @expected
      
      # Otherwise, pass.
      {length, nil}
    end
  end
end
