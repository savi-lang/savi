module Mare
  class Source
    property path : String
    property content : String
    def initialize(@path, @content)
    end
    NONE = new("(none)", "")
    def self.none; NONE end
  end
  
  struct SourcePos
    property source : Source
    property start : Int32
    property finish : Int32
    def initialize(@source, @start, @finish)
    end
    NONE = new(Source.none, 0, 0)
    def self.none; NONE end
    
    # Override inspect to avoid verbosely printing Source#content every time.
    def inspect(io)
      io << "`#{source.path.split("/").last}:#{start}-#{finish}`"
    end
    
    # Look at the source content surrounding the position to calculate
    # the following pieces of information, returned as a NamedTuple.
    # - row: the zero-indexed vertical position in the text
    # - col: the zero-indexed horizontal position in the text
    # - line_start: the character offset of the start of this line
    # - line_finish: the character offset of the end of this line
    private def get_info
      # TODO: convert start and finish from byte offset to char offset first,
      # so that multi-byte characters are properly accounted for here.
      content = source.content
      
      line_start = content.rindex("\n", start)
      line_start = line_start ? line_start + 1 : 0
      
      line_finish = content.index("\n", start) || content.size
      line_finish = line_finish ? line_finish - 1 : content.size
      
      col = start - line_start
      
      row = 0
      cursor = start
      while cursor && cursor > 0
        cursor -= 1
        cursor = content.rindex("\n", cursor.not_nil!)
        break if cursor.nil?
        row += 1
      end
      
      {
        row: row,
        col: col,
        line_start: line_start,
        line_finish: line_finish,
      }
    end
    
    def show
      content = source.content
      info = get_info
      
      twiddle_width = finish - start
      twiddle_width = 1 if twiddle_width == 0
      twiddle_width -= 1
      
      [
        "from #{source.path}:#{info[:row] + 1}:",
        content[info[:line_start]..info[:line_finish]],
        (" " * info[:col]) + "^" + ("~" * twiddle_width),
      ].join("\n")
    end
  end
end
