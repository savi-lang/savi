require "lsp" # only for conversion to/from LSP data types

struct Savi::Source
  property dirname : String
  property filename : String
  property content : String
  property library : Library
  property language : Symbol

  def initialize(@dirname, @filename, @content, @library, @language = :savi)
  end

  def path
    File.join(@dirname, @filename)
  end

  def entire_pos
    Source::Pos.index_range(self, 0, content.bytesize)
  end

  NONE = new("", "(none)", "", Library::NONE)
  def self.none; NONE end

  def self.new_example(content)
    new("", "(example)", content, Library.new(""))
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
  property start : Int32       # the byte offset of the start of this token
  property finish : Int32      # the byte offset of the end of this token
  property row : Int32         # the zero-based vertical position of the start
  property col : Int32         # the zero-based horizontal position of the start
  property line_start : Int32  # the byte offset of the start of the first line
  property line_finish : Int32 # the byte offset of the end of the first line

  def self.point(source : Source, row : Int32, col : Int32)
    current_row = 0
    line_start = 0

    while current_row < row
      current_row += 1
      line_start =
        source.content.byte_index('\n', line_start).try(&.+(1)) \
        || source.content.bytesize
    end

    line_finish = source.content.byte_index('\n', line_start) || source.content.bytesize
    start = line_start + col

    new(source, start, start, line_start, line_finish, row, col)
  end

  def self.point(source : Source, offset : Int32)
    offset = source.content.bytesize - 1 if offset >= source.content.bytesize

    line_start = 0
    line_finish = source.content.byte_index('\n') || source.content.bytesize
    row = 0

    while line_finish < offset
      line_start = line_finish + 1
      line_finish = source.content.byte_index('\n', line_start) || source.content.bytesize
      row += 1
    end

    col = offset - line_start

    new(source, offset, offset, line_start, line_finish, row, col)
  end

  def self.index_range(source : Source, new_start : Int32, new_finish : Int32)
    # TODO: dedup with similar logic in span and subset
    new_row = 0
    new_line_start = 0
    source.content.byte_slice(0, new_start).each_byte.each_with_index do |char, index|
      next unless char.chr == '\n'
      new_row += 1
      new_line_start = index + 1
    end
    new_line_finish = (source.content.byte_index('\n', new_line_start) || source.content.bytesize)
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

  def size
    finish - start
  end

  def single_line?
    finish <= line_finish
  end

  def contains?(other : Source::Pos?)
    return false unless other
    source == other.source &&
    start <= other.start &&
    finish >= other.finish
  end

  def contains_on_first_line?(other : Source::Pos?)
    return false unless other && contains?(other)
    other.start <= line_finish
  end

  def contains_on_last_line?(other : Source::Pos?)
    return false unless other && contains?(other)
    source.content.byte_rindex('\n', finish) == source.content.byte_rindex('\n', other.finish)
  end

  def precedes_on_same_line?(other : Source::Pos?)
    return false unless other
    source == other.source &&
    (
      source.content.byte_index('\n', finish) ==
      source.content.byte_index('\n', other.start)
    )
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

    content.byte_slice(0, trim_left).each_byte.each_with_index do |char, index|
      next unless char.chr == '\n'
      new_row += 1
      new_line_start = @line_start + index
    end
    new_line_finish = (source.content.byte_index('\n', new_line_start) || source.content.bytesize)
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
      next if other.source == Source.none

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
      source.content[0...new_start].each_byte.each_with_index do |char, index|
        next unless char.chr == '\n'
        new_row += 1
        new_line_start = @line_start + index
      end
      new_line_finish = (source.content.byte_index('\n', new_line_start) || source.content.bytesize)
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

  def next_byte?(offset = 0)
    source.content.byte_at?(finish + offset).try(&.chr)
  end

  def content_match_as_pos(pattern, match_index = 0)
    match = pattern.match_at_byte_index(content, 0)
    return unless match

    Pos.index_range(
      source,
      start + match.byte_begin(match_index),
      start + match.byte_end(match_index)
    )
  end

  def pre_match_as_pos(pattern, match_index = 0)
    match = pattern.match_at_byte_index(source.content.byte_slice(0, start), 0)
    return unless match

    Pos.index_range(
      source,
      match.byte_begin(match_index),
      match.byte_end(match_index)
    )
  end

  def post_match_as_pos(pattern, match_index = 0)
    match = pattern.match_at_byte_index(source.content, finish)
    return unless match

    Pos.index_range(
      source,
      match.byte_begin(match_index),
      match.byte_end(match_index)
    )
  end

  def get_indent
    match = /\G[ \t]+/.match_at_byte_index(source.content, line_start)
    new_finish = match ? match.byte_end(0) : line_start

    Pos.new(
      @source, @line_start, new_finish,
      @line_start, @line_finish,
      @row, 0,
    )
  end

  def get_prior_row_indent
    new_line_finish = @line_start - 1
    new_line_start = source.content.byte_rindex('\n', new_line_finish)
    return nil unless new_line_start

    new_line_start += 1

    match = /\G[ \t]+/.match_at_byte_index(source.content, new_line_start)
    new_finish = match ? match.byte_end(0) : new_line_start

    Pos.new(
      @source, new_line_start, new_finish,
      new_line_start, new_line_finish,
      @row - 1, 0,
    )
  end

  def get_finish_row_indent
    new_row = @row
    new_line_start = @line_start
    new_line_finish = @line_finish
    while new_line_finish < @finish
      new_row += 1
      new_line_start = new_line_finish + 1
      new_line_finish = source.content.byte_index('\n', new_line_start) || source.content.bytesize
    end

    match = /\G[ \t]+/.match_at_byte_index(source.content, new_line_start)
    new_finish = match ? match.byte_end(0) : new_line_start

    Pos.new(
      @source, new_line_start, new_finish,
      new_line_start, new_line_finish,
      new_row, 0,
    )
  end

  def show
    twiddle_width = finish - start
    twiddle_width = 1 if twiddle_width == 0
    twiddle_width -= 1

    tail = ""
    max_width = [0, line_finish - line_start - col - 1].max
    if twiddle_width > max_width
      twiddle_width = max_width
      tail = "···"
    end

    [
      "from #{source.path}:#{row + 1}:",
      source.content.byte_slice(line_start, line_finish - line_start),
      (" " * col) + "^" + ("~" * twiddle_width) + tail,
    ].join("\n")
  end

  def self.from_lsp_position(source, position : LSP::Data::Position)
    # TODO: we actually need to convert the character offset to a byte offset
    point(source, position.line.to_i32, position.character.to_i32)
  end

  def self.from_lsp_range(source, range : LSP::Data::Range)
    start = from_lsp_position(source, range.start)
    finish = from_lsp_position(source, range.finish)

    new(
      source, start.start, finish.start,
      start.line_start, start.line_finish,
      start.row, start.col
    )
  end

  def to_lsp_range
    # TODO: we actually need to convert the byte offsets to character offsets
    LSP::Data::Range.new(
      LSP::Data::Position.new(row.to_i64, col.to_i64),
      LSP::Data::Position.new(row.to_i64, (col + size).to_i64), # TODO: account for spilling over into a new row
    )
  end

  def to_lsp_location
    LSP::Data::Location.new(URI.new(path: source.path), to_lsp_range)
  end
end
