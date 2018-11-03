require "lsp"

class Mare::Server
  def initialize(
    @stdin : IO = STDIN,
    @stdout : IO = STDOUT,
    @stderr : IO = STDERR)
    @wire = LSP::Wire.new(@stdin, @stdout)
  end
  
  def run
    setup
    loop { handle @wire.receive }
  end
  
  def setup
    @stderr.puts("LSP Server is starting...")
    
    at_exit do
      @stderr.puts("... the LSP Server is closed.")
    end
    
    spawn do
      loop do
        if Process.ppid == 1
          @stderr.puts("... the LSP Server has been orphaned.")
          Process.exit(1)
        else
          sleep 30.seconds
        end
      end
    end
  end
  
  def handle(msg : LSP::Message::Initialize)
    @wire.respond msg do |msg|
      msg.result.capabilities.hover_provider = true
      msg.result.capabilities.text_document_sync.open_close = true
      msg.result.capabilities.text_document_sync.change =
        LSP::Data::TextDocumentSyncKind::Full
      msg
    end
  end
  
  def handle(msg : LSP::Message::Initialized)
    # Start server resources
  end
  
  def handle(msg : LSP::Message::Shutdown)
    # Stop server resources
    @wire.respond(msg) { |msg| msg }
  end
  
  def handle(msg : LSP::Message::Exit)
    Process.exit
  end
  
  # TODO: Hover support.
  def handle(msg : LSP::Message::Hover)
    pos = msg.params.position
    @wire.respond msg do |msg|
      msg.result.contents.kind = "markdown"
      msg.result.contents.value = "# TODO: Hover\n`#{pos.to_json}`"
      msg
    end
  end
  
  def handle(msg)
    @stderr.puts "Unhandled incoming message!"
    @stderr.puts msg.to_json
  end
end
