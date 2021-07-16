struct Savi::Source
  property dirname : String
  property filename : String
  property content : String
  property library : Library
  property language : Symbol

  def initialize(@dirname, @filename, @content, @library, @language = :savi)
  end

  def pony?
    @language == :pony
  end

  def path
    File.join(@dirname, @filename)
  end

  NONE = new("", "(none)", "", Library::NONE)
  def self.none; NONE end

  def self.new_example(content)
    new("", "(example)", content, Library.new(""))
  end

  def self.new_pony_example(content)
    new("", "(example)", content, Library.new(""), :pony)
  end
end

struct Savi::Source::Library
  property path : String

  def initialize(@path)
  end

  NONE = new("")
  def self.none; NONE end
end

struct Savi::Source::Pos
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
        || source.content.bytesize
    end

    line_finish = source.content.index("\n", line_start) || source.content.bytesize
    start = line_start + col

    new(source, start, start, line_start, line_finish, row, col)
  end

  def self.point(source : Source, offset : Int32)
    offset = source.content.bytesize - 1 if offset >= source.content.bytesize

    line_start = 0
    line_finish = source.content.index("\n") || source.content.bytesize
    row = 0

    while line_finish < offset
      line_start = line_finish + 1
      line_finish = source.content.index("\n", line_start) || source.content.bytesize
      row += 1
    end

    col = offset - line_start

    new(source, offset, offset, line_start, line_finish, row, col)
  end

  def self.index_range(source : Source, new_start : Int32, new_finish : Int32)
    # TODO: dedup with similar logic in span and subset
    new_row = 0
    new_line_start = 0
    source.content.byte_slice(0, new_start).each_char.each_with_index do |char, index|
      next unless char == '\n'
      new_row += 1
      new_line_start = index
    end
    new_line_finish = (source.content.index("\n", new_line_start) || source.content.bytesize) - 1
    new_col = new_start - new_line_start

    new(
      source, new_start, new_finish,
      new_line_start, new_line_finish,
      new_row, new_col
    )
  end

  def self.show_library_path(library : Library)
    source = Source.new(library.path, "", library.path, library, :path)
    new(source, 0, library.path.bytesize, 0, library.path.bytesize, 0, 0)
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

    # TODO: dedup with similar logic in span
    new_row = @row
    new_line_start = @line_start

    content.byte_slice(0, trim_left).each_char.each_with_index do |char, index|
      next unless char == '\n'
      new_row += 1
      new_line_start = @line_start + index
    end
    new_line_finish = (source.content.index("\n", new_line_start) || source.content.bytesize) - 1
    new_col = new_start - new_line_start

    self.class.new(
      source, new_start, new_finish,
      new_line_start, new_line_finish,
      new_row, new_col,
    )
  end

  def span(others : Enumerable(Source::Pos))
    new_start = @start
    new_finish = @finish
    others.each do |other|
      raise ArgumentError.new "can't span positions from different sources" \
        unless other.source == source

      new_start = other.start if other.start < @start
      new_finish = other.finish if other.finish > @finish
    end

    if new_start == @start
      # This is an optimized path for the common case of start not changing.
      self.class.new(source, @start, new_finish, @line_start, @line_finish, @row, @col)
    else
      # TODO: dedup with similar logic in subset
      new_row = @row
      new_line_start = @line_start
      source.content[0...new_start].each_char.each_with_index do |char, index|
        next unless char == '\n'
        new_row += 1
        new_line_start = @line_start + index
      end
      new_line_finish = (source.content.index("\n", new_line_start) || source.content.bytesize) - 1
      new_col = new_start - new_line_start

      self.class.new(
        source, new_start, new_finish,
        new_line_start, new_line_finish,
        new_row, new_col,
      )
    end
  end

  # Override inspect to avoid verbosely printing Source#content every time.
  def inspect(io)
    io << "`#{source.filename}:#{start}-#{finish}`"
  end

  def content
    source.content.byte_slice(start, finish - start)
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
      source.content.byte_slice(line_start, line_finish - line_start + 1),
      (" " * col) + "^" + ("~" * twiddle_width) + tail,
    ].join("\n")
  end
end
