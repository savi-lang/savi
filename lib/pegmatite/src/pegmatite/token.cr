module Pegmatite
  # A Token is a triple containing a name, a start offset, and end offset,
  # representing a named pattern that was matched within the overall pattern.
  alias Token = {Symbol, Int32, Int32}
end
