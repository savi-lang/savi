# TokenIterator is used to traverse a flat array of Tokens as if it were a tree.
#
# Child tokens in the tokens array are represented as tokens that follow after
# their parent in the array and have an offset range whose finish offset is
# less than or equal to the the finish offset of the parent.
#
# TokenIterator is aware of this relationship and can be used to easily
# traverse them, given a little discipline on the part of the caller.
# In particular, the caller must commit to consuming tokens in a depth-first
# traversal pattern in order for child relationships to be propery observed.
#
# See spec/fixtures/json.cr for a real-world example of using TokenIterator.
class Pegmatite::TokenIterator
  def initialize(@tokens : Array(Token), @offset = 0)
  end
  
  # Return the next token without consuming it.
  # Returns nil if the end of the token stream has been reached.
  def peek: Token?
    @tokens[@offset]?
  end
  
  # Consume the next token and return it.
  # Raises IndexError if the end of the token stream has been reached.
  def next: Token
    @tokens[@offset].tap { @offset += 1 }
  end
  
  # Return the next token without consuming it, if it is a child of parent.
  # Returns nil if isn't a child, or if at the end of the token stream.
  def peek_as_child_of(parent : Token): Token?
    child = @tokens[@offset]?
    
    child if child.is_a?(Token) && child[2] <= parent[2]
  end
  
  # Consume the next token if it is a child of parent and return it.
  # Raises IndexError if isn't a child, or if at the end of the token stream.
  def next_as_child_of(parent : Token): Token
    child = @tokens[@offset]
    
    raise IndexError.new("#{@offset} is not a child of #{parent}: #{child}") \
      if child[2] > parent[2]
    
    @offset += 1
    child
  end
  
  # Raise IndexError if the next token is a child of the given parent token.
  def assert_next_not_child_of(parent : Token)
    child = peek_as_child_of(parent)
    
    raise IndexError.new("#{@offset} is a child of #{parent}: #{child}") \
      if child
  end
  
  # For each next token that is a child of the given parent, yield it.
  #
  # This method assumes that the code in the block calls this recursively
  # or otherwise deals with any nested children of the yielded child token,
  # in a pattern of depth-first traversal, because that is how the original
  # flat token array is ordered. If this pattern is not followed then there
  # is no guarantee that the following yields from this method will be correct.
  def while_next_is_child_of(parent : Token)
    while @offset < @tokens.size
      child = @tokens[@offset]
      break if child[2] > parent[2]
      
      @offset += 1
      yield child
    end
  end
end
