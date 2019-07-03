require "uuid"

class LSP::Wire
  def initialize(@in : IO, @out : IO)
    @started = false
    @incoming = Channel(Message::Any).new
    @outstanding = {} of (String | Int64) => Message::AnyRequest
  end
  
  # Wait for the next Message::Any to arrive from the input IO channel.
  # Malformed data on the IO channel is silently ignored.
  # Raises Channel::ClosedError if the end of the IO has been reached.
  def receive
    if !@started
      @started = true
      spawn do
        loop do
          begin
            msg = LSP::Codec.read_message(@in, @outstanding)
            @incoming.send msg
          rescue IO::EOFError
            @incoming.close
            break
          end
        end
      end
    end
    @incoming.receive
  end
  
  def notify(m_class : M.class): M forall M
    msg : M = yield M.new
    LSP::Codec.write_message(@out, msg, @outstanding)
    msg
  end
  
  def request(m_class : M.class): M forall M
    msg : M = yield M.new(UUID.random.to_s)
    LSP::Codec.write_message(@out, msg, @outstanding)
    msg
  end
  
  def respond(req : M): M::Response forall M
    msg : M::Response = yield req.new_response
    LSP::Codec.write_message(@out, msg, @outstanding)
    msg
  end
  
  def error_respond(req : M): M::ErrorResponse forall M
    msg : M::ErrorResponse = yield req.new_error_response
    LSP::Codec.write_message(@out, msg, @outstanding)
    msg
  end
end
