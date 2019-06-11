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
  
  def initialize(
    @source, @start, @finish, @line_start, @line_finish, @row, @col
  )
  end
  NONE = new(Source.none, 0, 0, 0, 0, 0, 0)
  def self.none; NONE end
  
  # Override inspect to avoid verbosely printing Source#content every time.
  def inspect(io)
    io << "`#{source.filename}:#{start}-#{finish}`"
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
