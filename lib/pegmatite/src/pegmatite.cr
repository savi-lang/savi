require "./pegmatite/*"

module Pegmatite
  VERSION = "0.1.0"
  
  # Return the array of tokens resulting from executing the given pattern
  # grammar over the given source string, starting from the given offset.
  # Raises a Pattern::MatchError if parsing fails.
  def self.tokenize(
    pattern : Pattern,
    source : String,
    offset = 0,
  ) : Array(Token)
    state = Pattern::MatchState.new
    length, result = pattern.match(source, offset, state)
    
    case result
    when Pattern
      raise Pattern::MatchError.new(source, state.highest_fail)
    when Token
      [result]
    when Array(Token)
      result
    else
      [] of Token
    end
  end
end
