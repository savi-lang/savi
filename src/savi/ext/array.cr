class ::Array(T)
  # Convenience setter for overwriting the last element in the array,
  # raising an IndexError if this is not possible because the array is empty.
  def last=(value)
    raise IndexError.new if empty?
    @buffer[size - 1] = value
  end
end
