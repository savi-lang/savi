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

  # Raise an error for the given source position, with the given message.
  def self.at(any, msg : String); at(any.pos, msg) end
  def self.at(pos : Source::Pos, msg : String)
    raise new(pos, msg)
  end

  # Raise an error for the given source position, with the given message,
  # along with extra details taken from the following array of tuples.
  def self.at(any, msg : String, info); at(any.pos, msg, info) end
  def self.at(pos : Source::Pos, msg : String, info)
    new(pos, msg).tap do |err|
      info.each do |info_any, info_msg|
        info_pos = info_any.is_a?(Source::Pos) ? info_any : info_any.pos
        err.info << {info_pos, info_msg}
      end
      raise err
    end
  end
end
