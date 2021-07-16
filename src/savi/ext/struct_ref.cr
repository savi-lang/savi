# This class is used as a workaround for cases where we want to have a struct
# field that otherwise would break the rule that a struct cannot contain itself.
#
# Basically, this lets us sort of pretend of have referential transparency
# by wrapping a struct in a class that forwards all methods to the struct.
class StructRef(T)
  property value : T

  forward_missing_to @value

  def initialize(@value)
  end

  def ==(other : StructRef(T))
    value == other.value
  end
  def ==(other_value : T)
    value == other_value
  end

  def hash(hasher)
    value.hash(hasher)
  end

  def to_s(io)
    value.to_s(io)
  end

  def inspect(io)
    value.inspect(io)
  end

  def pretty_print(pp)
    value.pretty_print(pp)
  end
end
