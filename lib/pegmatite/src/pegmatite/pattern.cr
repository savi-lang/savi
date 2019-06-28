abstract class Pegmatite::Pattern
  include DSL::Methods
  
  # A successful match returns zero, one, or many tokens.
  # We treat zero (Nil) and one (Token) as special cases so that we don't have
  # to pay to allocate an Array(Token) on every single match method call.
  alias MatchOK = Nil | Token | Array(Token)
  
  # Calling a match method will return the number of bytes consumed,
  # followed in the tuple by either MatchOK or a Pattern instance,
  # the latter indicating that the indicated pattern failed to match.
  alias MatchResult = {Int32, MatchOK | Pattern}
  
  # MatchState is a class that carries some state through a match method.
  # It's not meant to be used as part of any public API.
  class MatchState
    property tokenize : Bool
    getter highest_fail : {Int32, Pattern}
    
    def initialize(@tokenize = true)
      @highest_fail = {-1, UnicodeAny::INSTANCE}
    end
    
    def observe_fail(offset, pattern)
      @highest_fail = {offset, pattern} if offset > @highest_fail[0]
    end
  end
  
  # Higher-level methods may choose to represent errors as exceptions,
  # created in part by getting the description of the Pattern that failed.
  class MatchError < Exception
    def initialize(source, fail : {Int32, Pattern})
      offset, pattern = fail
      description = pattern.description
      
      line_start = (source.rindex("\n", [offset - 1, 0].max) || -1) + 1
      line_finish = (source.index("\n", offset) || source.size)
      
      line = source[line_start...line_finish]
      cursor = " " * (offset - line_start) + "^"
      
      # TODO: Use pattern.description after reliably getting the right pattern.
      # TODO: Report source name/filename and line number too.
      super("unexpected token at byte offset #{offset}:\n#{line}\n#{cursor}")
    end
  end
end

require "./pattern/*"
