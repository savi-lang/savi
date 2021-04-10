require "bit_array"

# Seriously, what's the fun of having a BitArray type in Crystal's stdlib
# if you can't even do bitwise operations on them?! We'll have our fun here.
struct BitArray
  # Return a new BitArray whose bits are the union of those in self and other.
  # Raises an ArgumentError if the two BitArrays are not the same size.
  def |(other : BitArray) : BitArray
    result = BitArray.new(@size)
    @bits.copy_to(result.@bits, malloc_size)
    result.apply_bitwise_or_from(other)
    result
  end
  protected def apply_bitwise_or_from(other : BitArray)
    raise ArgumentError.new \
      "other BitArray has size #{other.size} but our size is #{size}" \
        unless other.size == size

    malloc_size.times do |i|
      @bits[i] |= other.@bits[i]
    end

    self
  end

  # Return a BitArray containing those bits that are in both self and other,
  # or nil if there are no bits that intersect between the two.
  # Raises an ArgumentError if the two BitArrays are not the same size.
  # There are easier ways to do this, but we want to optimize for not
  # producing a new BitArray unless it is absolutely necessary.
  def intersection?(other : BitArray) : BitArray?
    raise ArgumentError.new \
      "other BitArray has size #{other.size} but our size is #{size}" \
        unless other.size == size

    disjoint_so_far = true
    equal_so_far = true
    new_result : BitArray? = nil

    malloc_size.times do |i|
      this_byte = @bits[i]
      that_byte = other.@bits[i]
      intersect_byte = this_byte & that_byte

      if new_result
        new_result.@bits[i] = intersect_byte

      elsif disjoint_so_far
        next if intersect_byte == 0
        disjoint_so_far = false

        next if equal_so_far && this_byte == that_byte

        new_result = BitArray.new(@size)
        new_result.@bits[i] = intersect_byte

      elsif equal_so_far
        next if this_byte == that_byte
        equal_so_far = false

        new_result = BitArray.new(@size)
        @bits.copy_to(new_result.@bits, i)
        new_result.@bits[i] = intersect_byte

      else
        raise "This branch should be unreachable!"
      end
    end

    if new_result
      new_result
    elsif disjoint_so_far
      nil
    elsif equal_so_far
      self
    end
  end
end
