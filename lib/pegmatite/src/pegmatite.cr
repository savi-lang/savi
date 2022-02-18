require "./pegmatite/*"

module Pegmatite
  VERSION = "0.1.0"

  # Return the array of tokens resulting from executing the given pattern
  # grammar over the given source string, starting from the given offset.
  # If an IO is passed, print traces of all parsing activity.
  # Raises a Pattern::MatchError if parsing fails.
  def self.tokenize(
    pattern : Pattern,
    source : String,
    offset = 0,
    io : IO? = nil
  ) : Array(Token)
    state = Pattern::MatchState.new
    state.trace = true if io
    _, result = pattern.match(source, offset, state)

    # If an IO is passed, print traces of all parsing activity.
    if io
      state.traces.each do |trace|
        case trace
        when {Pattern, Int32}
          io.puts "#{trace[1]} ?? #{trace[0].inspect}"
        when {Pattern, Int32, Pattern::MatchResult}
          trace_result = trace.as({Pattern, Int32, Pattern::MatchResult})[2]
          case trace_result[1]
          when Pattern::MatchOK
            io.puts "#{trace[1]} ~~~ #{trace[0].dsl_name} - #{trace_result.inspect}"
          else
            io.puts "#{trace[1]}     #{trace[0].dsl_name} - FAIL"
          end
        end
      end
    end

    case result
    when Pattern
      raise Pattern::MatchError.new(source, state.highest_fail)
    when Token
      [result]
    when Array(Token)
      result
    else
      [] of Token
    end
  end
end
