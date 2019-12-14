require "pegmatite"

module Mare::Parser::Builder
  # This State is used mainly for keeping track of line numbers and ranges,
  # so that we can better populate a Source::Pos with all the info it needs.
  class State
    def initialize(@source : Source)
      @row = 0
      @line_start = 0
      @line_finish =
        ((@source.content.index("\n") || @source.content.size) - 1).as(Int32)
    end

    private def content
      @source.content
    end

    private def next_line
      @row += 1
      @line_start = @line_finish + 2
      @line_finish = (content.index("\n", @line_start) || content.size) - 1
    end

    private def prev_line
      @row -= 1
      @line_finish = @line_start - 2
      @line_start = (content.rindex("\n", @line_finish) || -1) + 1
    end

    def pos(token : Pegmatite::Token) : Source::Pos
      kind, start, finish = token

      while start < @line_start
        prev_line
      end
      while start > @line_finish + 1
        next_line
      end
      if start < @line_start
        raise "whoops"
      end
      col = start - @line_start

      Source::Pos.new(
        @source, start, finish, @line_start, @line_finish, @row, col,
      )
    end

    def slice(token : Pegmatite::Token)
      kind, start, finish = token
      slice(start...finish)
    end

    def slice(range : Range)
      content[range]
    end

    def slice_with_escapes(token : Pegmatite::Token)
      kind, start, finish = token
      slice_with_escapes(start...finish)
    end

    def slice_with_escapes(range : Range)
      string = content[range]
      reader = Char::Reader.new(string)

      String.build string.bytesize do |result|
        while reader.pos < string.bytesize
          case reader.current_char
          when '\\'
            case reader.next_char
            when '\\' then result << '\\'
            when '\'' then result << '\''
            when '"' then result << '"'
            when 'b' then result << '\b'
            when 'f' then result << '\f'
            when 'n' then result << '\n'
            when 'r' then result << '\r'
            when 't' then result << '\t'
            when 'u' then
              codepoint = 0
              4.times do
                hex_char = reader.next_char
                hex_value =
                  if '0' <= hex_char <= '9'
                    hex_char - '0'
                  elsif 'a' <= hex_char <= 'f'
                    10 + (hex_char - 'a')
                  elsif 'A' <= hex_char <= 'F'
                    10 + (hex_char - 'A')
                  else
                    raise "invalid unicode escape hex character: #{hex_char}"
                  end
                codepoint = 16 * codepoint + hex_value
              end
              result << codepoint
            else
              raise "invalid escape character: #{reader.current_char}"
            end
          else
            result << reader.current_char
          end
          reader.next_char
        end
      end
    end
  end
end
