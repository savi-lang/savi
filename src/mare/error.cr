# This exception class is used to represent errors to be presented to the user,
# with each error being associated to a particular SourcePos that caused it.
class Mare::Error < Exception
  # alias Details = Array(Tuple(Source::Pos))
  
  # Raise an error for the given source position, with the given message.
  def self.at(any, msg : String); at(any.pos, msg) end
  def self.at(pos : Source::Pos, msg : String)
    raise new("#{msg}:\n#{pos.show}")
  end
  
  # Raise an error for the given source position, with the given message,
  # along with extra details taken from the following array of tuples.
  def self.at(any, msg : String, extra); at(any.pos, msg, extra) end
  def self.at(pos : Source::Pos, msg : String, extra)
    lines = extra.map do |any, m|
      "\n- #{m}:\n  #{(any.is_a?(Source::Pos) ? any : any.pos).show}"
    end
    lines.unshift("#{msg}:\n#{pos.show}")
    raise new(lines.join("\n"))
  end
end
