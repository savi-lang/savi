class String
  # Crystal has index and rindex and byte_index, but no byte_rindex!
  # So we add it here, at least for the simple version of it that only takes
  # a single byte as its search term - we leave out the trickier string search.
  def byte_rindex(byte : Int, offset = bytesize)
    (offset - 1).downto(0) do |i|
      if to_unsafe[i] == byte
        return i
      end
    end
    nil
  end

  # We also provide convenience wrappers for using a Char as the search byte.
  def byte_index(char : Char, offset = 0)
    byte_index(char.ord, offset)
  end
  def byte_rindex(char : Char, offset = bytesize)
    byte_rindex(char.ord, offset)
  end

  # Convenience method to split on the given delimiter once, raising an error
  # if the delimiter wasn't found, and otherwise returning as a tuple.
  def split2!(separator : Char) : {String, String}
    array = split(separator, 2, remove_empty: true)
    raise ArgumentError.new \
      "expected #{self.inspect} to be splittable by #{separator.inspect}" \
        unless array.size == 2
    {array[0], array[1]}
  end
end
