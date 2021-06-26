require "./spec_helper"

describe LSP::Codec do
  it "can write and read a request and response" do
    outstanding = {} of (String | Int64) => LSP::Message::AnyRequest
    id = UUID.random.to_s

    # Create and write a request.
    req = LSP::Message::ShowMessageRequest.new(id)
    buf = IO::Memory.new
    LSP::Codec.write_message(buf, req, outstanding)

    # Confirm that writing it added an entry to our outstanding requests map.
    outstanding.size.should eq 1
    outstanding[id].should eq req

    # Read it back and compare it to the original request.
    LSP::Codec.read_message(IO::Memory.new(buf.to_s)).should eq req

    # Compare the request JSON to the expected string representation.
    buf.to_s.should eq \
      "Content-Length: 145\r\n\r\n" \
    "{\"method\":\"window/showMessageRequest\"," \
    "\"jsonrpc\":\"2.0\",\"id\":\"#{id}\",\"params\":{" \
    "\"type\":4,\"message\":\"\",\"actions\":[]}}\n"

    # Create and write the response.
    res = req.new_response
    buf = IO::Memory.new
    LSP::Codec.write_message(buf, res)

    # Read it back and compare it to the original response.
    LSP::Codec.read_message(IO::Memory.new(buf.to_s), outstanding).should eq res

    # Confirm that reading it removed the entry in our outstanding requests map.
    outstanding.size.should eq 0

    # Compare the response JSON to the expected string representation.
    buf.to_s.should eq \
      "Content-Length: 76\r\n\r\n" \
    "{\"jsonrpc\":\"2.0\",\"id\":\"#{id}\",\"result\":null}\n"
  end

  it "raises IO::EOFError when there are no bytes left to read" do
    expect_raises IO::EOFError do
      LSP::Codec.read_message(IO::Memory.new(""))
    end
  end

  it "raises IO::EOFError when only malformed lines are available to read" do
    expect_raises IO::EOFError do
      LSP::Codec.read_message(IO::Memory.new("mal\r\nformed\r\n"))
    end
  end

  it "reads a valid message preceded by malformed lines" do
    msg = LSP::Message::ShowMessage.new
    buf = IO::Memory.new
    buf.print("mal\r\nformed\r\n")
    LSP::Codec.write_message(buf, msg)

    LSP::Codec.read_message(IO::Memory.new(buf.to_s)).should eq msg
  end
end
