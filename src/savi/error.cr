require "lsp" # only for conversion to/from LSP data types

# This exception class is used to represent errors to be presented to the user,
# with each error being associated to a particular SourcePos that caused it.
class Savi::Error < Exception
  alias Info = {Source::Pos, String}

  protected setter cause
  getter pos : Source::Pos
  getter headline : String
  getter info = [] of {Source::Pos, String}
  getter fix_edits = [] of {Source::Pos, String}

  def initialize(@pos, @headline)
    @info = [] of {Source::Pos, String}
  end

  def ==(other : Error)
    @pos == other.pos && \
    @headline == other.headline && \
    @info == other.info
  end

  def message(show_compiler_hole_details = false)
    strings =
      if pos == Source::Pos.none
        ["#{headline}\n"]
      else
        ["#{headline}:\n#{pos.show}\n"]
      end
    info.each do |info_pos, info_msg|
      if info_pos == Source::Pos.none
        strings << "- #{info_msg}"
      else
        strings << "- #{info_msg}:\n  #{info_pos.show}\n"
      end
    end
    if fix_edits.any?
      strings << "- run again with --fix to auto-fix this issue."
    end
    # If a causing exception is present, this indicates a compiler hole.
    cause.try { |cause|
      strings << if show_compiler_hole_details
        "- Because you ran the compiler with the --backtrace option, " +
        "the full backtrace of the original error is shown below:\n\n" +
        cause.inspect_with_backtrace
      else
        "- To report a ticket or investigate the missing logic yourself, " +
        "rerun the compiler with --backtrace to see the full backtrace."
      end
    }
    strings.join("\n").strip
  end

  def to_lsp_diagnostic
    LSP::Data::Diagnostic.new(
      range: pos.to_lsp_range,
      message: message, # TODO: should this use the headline instead?
      related_information: info.map { |info_pos, info_message|
        LSP::Data::Diagnostic::RelatedInformation.new(
          info_pos.to_lsp_location,
          info_message,
        )
      }
    )
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
  def self.build(any, msg : String, info, fix_edits = nil)
    build(any.pos, msg, info, fix_edits)
  end
  def self.build(pos : Source::Pos, msg : String, info, fix_edits = nil)
    new(pos, msg).tap do |err|
      info.each do |info_any, info_msg|
        info_pos = info_any.is_a?(Source::Pos) ? info_any : info_any.pos
        err.info << {info_pos, info_msg}
      end
      fix_edits.try(&.each { |fix_edit|
        err.fix_edits << fix_edit
      })
    end
  end

  def self.compiler_hole_at(pos, cause : Exception)
    return cause if cause.is_a?(Error)

    build(pos, "An unexpected compiler error occurred near here").tap { |err|
      err.cause = cause
      err.info << {Source::Pos.none,
        "The compiler is missing logic to handle this code."}
      err.info << {Source::Pos.none,
        "Usually this means your code is invalid, and we just failed " +
        "to have a helpful explanation here as to what you did wrong, " +
        "but it's possible that your code is fine and there is a deeper bug. " +
        "Either way, if you see this message, it counts as a compiler hole " +
        "that needs to be patched up to give users like you a good experience."}
    }
  end
end
