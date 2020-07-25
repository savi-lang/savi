class Array(T)
  def duplicate_value
    group_by { |i| i }.reject { |_, v| v.size == 1 }.keys
  end
end
