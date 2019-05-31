module Pegmatite
  # Pattern::UnicodeAny is used to consume any single arbitrary character.
  #
  # Parsing will fail if a valid UTF-32 codepoint couldn't be parsed.
  # Otherwise, the pattern succeeds, consuming the matched bytes.
  class Pattern::UnicodeAny < Pattern
    # This class is stateless, so to save memory, you can use this singleton
    # INSTANCE instead of allocating a new one every time.
    INSTANCE = new
    
    # This helper method is used to extract a UTF-32 codepoint from the given
    # byte offset of the given source string, returning the codepoint itself
    # along with the number of bytes that were consumed by its representation.
    def self.utf32_at(source, offset) : {UInt32, Int32}
      err = {0xFFFD_u32, 1}
      
      # Get the first byte in the character.
      return err if source.bytesize <= offset
      c = source.unsafe_byte_at(offset).to_u32
      
      if c < 0x80_u32
        # This is a one-byte character.
        {c, 1}
      elsif c < 0xC2_u32
        # This is a stray continuation.
        err
      elsif c < 0xE0_u32
        # This is a two-byte character.
        return err if source.bytesize <= offset + 1
        c2 = source.unsafe_byte_at(offset + 1).to_u32
        
        # Make sure the next byte is a continuation byte.
        return err if (c2 & 0xC0_u32) != 0x80_u32
        
        # Return the two-byte character.
        {((c << 6) + c2) - 0x3080_u32, 2}
      elsif c < 0xF0_u32
        # This is a three-byte character.
        return err if source.bytesize <= offset + 2
        c2 = source.unsafe_byte_at(offset + 1).to_u32
        c3 = source.unsafe_byte_at(offset + 2).to_u32
        
        # Make sure the next bytes are continuation bytes.
        return err if (c2 & 0xC0_u32) != 0x80_u32
        return err if (c3 & 0xC0_u32) != 0x80_u32
        
        # Make sure the encoding is not overlong.
        return err if (c == 0xE0_u32) && (c2 < 0xA0_u32)
        
        # Return the three-byte character.
        {((c << 12) + (c2 << 6) + c3) - 0xE2080_u32, 3}
      elsif c < 0xF5_u32
        # This is a four-byte character.
        return err if source.bytesize <= offset + 3
        c2 = source.unsafe_byte_at(offset + 1).to_u32
        c3 = source.unsafe_byte_at(offset + 2).to_u32
        c4 = source.unsafe_byte_at(offset + 3).to_u32
        
        # Make sure the next bytes are continuation bytes.
        return err if (c2 & 0xC0_u32) != 0x80_u32
        return err if (c3 & 0xC0_u32) != 0x80_u32
        return err if (c4 & 0xC0_u32) != 0x80_u32
        
        # Make sure the encoding is not overlong.
        return err if (c == 0xF0_u32) && (c2 < 0x90_u32)
        
        # Make sure the result will be <= 0x10FFFF.
        return err if (c == 0xF4_u32) && (c2 >= 0x90_u32)
        
        # Return the four-byte character.
        {((c2 << 18) + (c2 << 12) + (c3 << 6) + c4) - 0x3C82080_u32, 4}
      else
        # The result would not be <= 0x10FFFF.
        err
      end
    end
    
    def description
      "any character"
    end
    
    def match(source, offset, state) : MatchResult
      c, length = Pattern::UnicodeAny.utf32_at(source, offset)
      
      # Fail if a valid UTF-32 character couldn't be parsed.
      return {0, self} if c == 0xFFFD_u32
      
      # Otherwise, pass.
      {length, nil}
    end
  end
end
