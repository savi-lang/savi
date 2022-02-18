module Pegmatite
  # Pattern::DynamicMatch is used to match against a stored dynamic match value
  # and consume the string that matches the stored dynamic match.
  #
  # Parsing will fail if the bytes in the stream don't exactly match the dynamic
  # match. Otherwise, the pattern succeeds, consuming the matched bytes.
  class Pattern::DynamicMatch < Pattern
    def initialize(@label : Symbol)
    end

    def inspect(io)
      io << "dynamic_match(\""
      @label.inspect(io)
      io << "\")"
    end

    def dsl_name
      "dynamic_match"
    end

    def description
      @label.inspect
    end

    def _match(source, offset, state) : MatchResult
      last_delim = state.dynamic_matches.reverse_each.find { |delim|
        delim[0] == @label
      }

      if !last_delim
        return {0, self}
      end

      delim_val = last_delim[1]
      delim_size = delim_val.bytesize.as(Int32)

      # Like Literal, we use some ugly patterns here for optimization
      return {0, self} if source.bytesize < (offset + delim_size)
      i = 0
      while i < delim_size
        return {0, self} \
           if delim_val.to_unsafe[i] != source.to_unsafe[offset + i]
        i += 1
      end

      {delim_val.bytesize, nil}
    end
  end
end
