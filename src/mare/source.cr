class Mare::Source
  property filename : String
  property content : String
  property library : Library
  
  def initialize(@filename, @content, @library)
  end
  
  def path
    File.join(@library.path, @filename)
  end
  
  NONE = new("(none)", "", Library::NONE)
  def self.none; NONE end
  
  def self.new_example(content)
    new("(example)", content, Library.new(""))
  end
end

class Mare::Source::Library
  property path : String
  
  def initialize(@path)
  end
  
  NONE = new("")
  def self.none; NONE end
end

struct Mare::Source::Pos
  property source : Source
  property start : Int32       # the character offset of the start of this token
  property finish : Int32      # the character offset of the end of this token
  property row : Int32         # the zero-based vertical position in the text
  property col : Int32         # the zero-based horizontal position in the text
  property line_start : Int32  # the character offset of the start of this line
  property line_finish : Int32 # the character offset of the end of this line
  
  def self.point(source : Source, row : Int32, col : Int32)
    current_row = 0
    line_start = 0
    
    while current_row < row
      current_row += 1
      line_start =
        source.content.index("\n", line_start).try(&.+(1)) \
        || source.content.size
    end
    
    line_finish = source.content.index("\n", line_start) || source.content.size
    start = line_start + col
    
    new(source, start, start, line_start, line_finish, row, col)
  end
  
  def initialize(
    @source, @start, @finish, @line_start, @line_finish, @row, @col
  )
  end
  NONE = new(Source.none, 0, 0, 0, 0, 0, 0)
  def self.none; NONE end
  
  def contains?(other : Source::Pos)
    source == other.source &&
    start <= other.start &&
    finish >= other.finish
  end
  
  def size
    finish - start
  end
  
  def subset(trim_left, trim_right)
    raise ArgumentError.new \
      "can't trim this much (#{trim_left}, #{trim_right}) of this:\n#{show}" \
      if (trim_left + trim_right) > size
    
    new_start = @start + trim_left
    new_finish = @finish - trim_right
    
    new_row = @row
    new_line_start = @line_start
    content[0...trim_left].each_char.each_with_index do |char, index|
      next unless char == '\n'
      new_row += 1
      new_line_start = @line_start + index
    end
    new_line_finish = source.content.index("\n", new_line_start) || source.content.size
    new_col = new_start - new_line_start
    
    self.class.new(
      source, new_start, new_finish,
      new_line_start, new_line_finish,
      new_row, new_col,
    )
  end
  
  # Override inspect to avoid verbosely printing Source#content every time.
  def inspect(io)
    io << "`#{source.filename}:#{start}-#{finish}`"
  end
  
  def content
    source.content[start...finish]
  end
  
  def show
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
      source.content[line_start..line_finish],
      (" " * col) + "^" + ("~" * twiddle_width) + tail,
    ].join("\n")
  end
end
