module Pegmatite
  # Pattern::Literal is used to consume a specific string.
  #
  # Parsing will fail if the bytes in the stream don't exactly match the string.
  # Otherwise, the pattern succeeds, consuming the matched bytes.
  class Pattern::Literal < Pattern
    def initialize(@string : String)
    end
    
    def description
      @string.inspect
    end
    
    def match(source, offset, state) : MatchResult
      if source.byte_slice(offset, @string.bytesize) == @string
        {@string.bytesize, nil}
      else
        {0, self}
      end
    rescue IndexError
      {0, self}
    end
  end
end
