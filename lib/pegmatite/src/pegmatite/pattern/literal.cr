module Pegmatite
  # Pattern::Literal is used to consume a specific string.
  #
  # Parsing will fail if the bytes in the stream don't exactly match the string.
  # Otherwise, the pattern succeeds, consuming the matched bytes.
  class Pattern::Literal < Pattern
    def initialize(@string : String)
      @size = @string.bytesize.as(Int32)
    end

    def inspect(io)
      io << "str(\""
      @string.inspect(io)
      io << "\")"
    end

    def dsl_name
      "str"
    end

    def description
      @string.inspect
    end

    def _match(source, offset, state) : MatchResult
      # We use some ugly patterns here for optimization - this is a hot path!
      return {0, self} if source.bytesize < (offset + @string.bytesize)
      i = 0
      while i < @size
        return {0, self} \
           if @string.to_unsafe[i] != source.to_unsafe[offset + i]
        i += 1
      end

      {@string.bytesize, nil}
    end
  end
end
