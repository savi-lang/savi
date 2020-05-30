class ::Array(T)
  # Map a function over each element in the array, with the map function either
  # returning the original element, or a new element of the same type.
  # If none of the original elements change, the original array is returned.
  # Otherwise, follow the copy-on-write pattern by allocating a new array
  # as soon as one element has changed, but otherwise avoiding allocation.
  def map_cow(&block : T -> T)
    changed = false

    # Avoid allocating new_list if no items change;
    # lazily allocate it after the first item has changed.
    new_list = nil
    self.each_with_index do |item, index|
      if changed
        new_list.not_nil! << yield item
      else
        new_item = yield item
        if new_item != item
          changed = true
          new_list = (self[0...index] << new_item)
        end
      end
    end

    new_list || self
  end

  # TODO: Figure out if map_cow2 can be efficiently unified with map_cow.
  def map_cow2(&block : T -> T)
    changed = false

    # Avoid allocating new_list if no items change;
    # lazily allocate it after the first item has changed.
    new_list = nil
    self.each_with_index do |(item1, item2), index|
      if changed
        new_list.not_nil! << yield ({item1, item2})
      else
        new_item1, new_item2 = yield ({item1, item2})
        if (new_item1 != item1) || (new_item2 != item2)
          changed = true
          new_list = (self[0...index] << {new_item1, new_item2})
        end
      end
    end

    new_list || self
  end
end
