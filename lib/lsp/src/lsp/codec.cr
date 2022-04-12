module LSP::Codec
  # Write a message using the LSP wire format, including headers.
  def self.write_message(
    io : IO,
    message : Message::Any,
    outstanding = {} of (String | Int64) => Message::AnyRequest
  )
    if message.is_a?(Message::AnyRequest)
      outstanding[message.id] = message
    end
    body = message.to_json
    io.print("Content-Length: #{body.bytesize + 1}\r\n\r\n")
    io.print(body)
    io.print("\n")
  end

  # Read a message using the LSP wire format, including headers.
  # Silently swallows malformed lines/messages that get in the way.
  # Raises IO::EOFError when the IO is out of data to be read.
  def self.read_message(
    io : IO,
    outstanding = {} of (String | Int64) => Message::AnyRequest
  ) : Message::Any
    # Keep trying until we get a valid message.
    loop do
      # Read all headers, taking note of the content length.
      length : Int32? = nil
      while (header = io.read_line)
        split = header.as(String).split(": ", 2)
        break if split.size < 2

        key, value = split
        case key
        when "Content-Length"
          length = value.to_i
        when "Content-Type"
          # ignore
        else break
        end
      end

      # Read the specified number of bytes, as JSON, into an LSP::Message.
      if length.is_a? Int32
        body = IO::Sized.new(io, length).gets_to_end
        raise IO::EOFError.new if body.bytesize < length
        begin
          return LSP::Message.from_json(body, outstanding)
        rescue
          # keep looping until we get a valid, recognized message
        end
      end
    end
  end
end
