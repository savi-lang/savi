# This exception class is used to represent errors to be presented to the user,
# with each error being associated to a particular SourcePos that caused it.
class Mare::Error < Exception
  alias Info = {Source::Pos, String}

  getter pos : Source::Pos
  getter headline : String
  getter info : Array(Info)

  def initialize(@pos, @headline)
    @info = [] of {Source::Pos, String}
  end

  def ==(other : Error)
    @pos == other.pos && \
    @headline == other.headline && \
    @info == other.info
  end

  def message
    strings = ["#{headline}:\n#{pos.show}\n"]
    info.each do |info_pos, info_msg|
      if info_pos == Source::Pos.none
        strings << "- #{info_msg}"
      else
        strings << "- #{info_msg}:\n  #{info_pos.show}\n"
      end
    end
    strings.join("\n").strip
  end

  # Raise an error built with the given information.
  def self.at(*args); raise build(*args) end

  # Build an error for the given source position, with the given message.
  def self.build(any, msg : String) : Error; build(any.pos, msg) end
  def self.build(pos : Source::Pos, msg : String) : Error
    new(pos, msg)
  end

  # Raise an error for the given source position, with the given message,
  # along with extra details taken from the following array of tuples.
  def self.build(any, msg : String, info); build(any.pos, msg, info) end
  def self.build(pos : Source::Pos, msg : String, info)
    new(pos, msg).tap do |err|
      info.each do |info_any, info_msg|
        info_pos = info_any.is_a?(Source::Pos) ? info_any : info_any.pos
        err.info << {info_pos, info_msg}
      end
    end
  end
end
