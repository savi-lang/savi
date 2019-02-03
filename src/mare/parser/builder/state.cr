require "pegmatite"

module Mare::Parser::Builder
  # This State is used mainly for keeping track of line numbers and ranges,
  # so that we can better populate a Source::Pos with all the info it needs.
  class State
    def initialize(@source : Source)
      @row = 0
      @line_start = 0
      @line_finish =
        ((@source.content.index("\n") || @source.content.size) - 1).as(Int32)
    end
    
    private def content
      @source.content
    end
    
    private def next_line
      @row += 1
      @line_start = @line_finish + 2
      @line_finish = (content.index("\n", @line_start) || content.size) - 1
    end
    
    private def prev_line
      @row -= 1
      @line_finish = @line_start - 2
      @line_start = (content.rindex("\n", @line_finish) || -1) + 1
    end
    
    def pos(token : Pegmatite::Token) : Source::Pos
      kind, start, finish = token
      
      while start < @line_start
        prev_line
      end
      while start > @line_finish + 1
        next_line
      end
      if start < @line_start
        raise "whoops"
      end
      col = start - @line_start
      
      Source::Pos.new(
        @source, start, finish, @line_start, @line_finish, @row, col,
      )
    end
    
    def slice(token : Pegmatite::Token)
      kind, start, finish = token
      slice(start...finish)
    end
    
    def slice(range : Range)
      content[range]
    end
  end
end
