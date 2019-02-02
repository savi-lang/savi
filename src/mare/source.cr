class Mare::Source
  property path : String
  property content : String
  def initialize(@path, @content)
  end
  NONE = new("(none)", "")
  def self.none; NONE end
end

struct Mare::Source::Pos
  property source : Source
  property start : Int32
  property finish : Int32
  
  def initialize(@source, @start, @finish)
    @info = {0, 0, 0, 0}
    @missing_info = true
  end
  NONE = new(Source.none, 0, 0)
  def self.none; NONE end
  
  # Override inspect to avoid verbosely printing Source#content every time.
  def inspect(io)
    io << "`#{source.path.split("/").last}:#{start}-#{finish}`"
  end
  
  def row; info[0] end
  def col; info[1] end
  def line_start; info[2] end
  def line_finish; info[3] end
  
  # Look at the source content surrounding the position to calculate
  # the following pieces of information, returned as a NamedTuple.
  # - row: the zero-indexed vertical position in the text
  # - col: the zero-indexed horizontal position in the text
  # - line_start: the character offset of the start of this line
  # - line_finish: the character offset of the end of this line
  private def info
    return @info unless @missing_info
    
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
    
    @missing_info = false
    @info = {row, col, line_start, line_finish}
  end
  
  def show
    content = source.content
    
    twiddle_width = finish - start
    twiddle_width = 1 if twiddle_width == 0
    twiddle_width -= 1
    
    tail = ""
    max_width = [0, line_finish - line_start - col].max
    if twiddle_width > max_width
      twiddle_width = max_width
      tail = "···"
    end
    
    [
      "from #{source.path}:#{row + 1}:",
      content[line_start..line_finish],
      (" " * col) + "^" + ("~" * twiddle_width) + tail,
    ].join("\n")
  end
end
