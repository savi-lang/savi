require "lsp"
require "uri"

class Mare::Server
  def initialize(
    @stdin : IO = STDIN,
    @stdout : IO = STDOUT,
    @stderr : IO = STDERR)
    @wire = LSP::Wire.new(@stdin, @stdout)
    @open_files = {} of URI => String
    
    @use_snippet_completions = false
  end
  
  def run
    setup
    loop { handle @wire.receive }
  end
  
  def setup
    @stderr.puts("LSP Server is starting...")
    
    # Before we exit, say goodbye.
    at_exit do
      @stderr.puts("... the LSP Server is closed.")
    end
  end
  
  # When told to initialize, respond with info about our capabilities.
  def handle(msg : LSP::Message::Initialize)
    @use_snippet_completions =
      msg.params.capabilities
        .text_document.completion
        .completion_item.snippet_support
    
    @wire.respond msg do |msg|
      msg.result.capabilities.text_document_sync.open_close = true
      msg.result.capabilities.text_document_sync.change =
        LSP::Data::TextDocumentSyncKind::Full
      msg.result.capabilities.hover_provider = true
      msg.result.capabilities.completion_provider =
        LSP::Data::ServerCapabilities::CompletionOptions.new(false, [":"])
      msg
    end
  end
  
  # When told that we're free to be initialized, do so.
  def handle(msg : LSP::Message::Initialized)
    # TODO: Start server resources.
  end
  
  # When asked to shut down, respond in the affirmative immediately.
  def handle(msg : LSP::Message::Shutdown)
    # TODO: Stop server resources.
    @wire.respond(msg) { |msg| msg }
  end
  
  # When told that we're free to exit gracefully, do so.
  def handle(msg : LSP::Message::Exit)
    Process.exit
  end
  
  # When a text document is opened, store it in our local set.
  def handle(msg : LSP::Message::DidOpen)
    @open_files[msg.params.text_document.uri] =
      msg.params.text_document.text
  end
  
  # When a text document is changed, update it in our local set.
  def handle(msg : LSP::Message::DidChange)
    @open_files[msg.params.text_document.uri] =
      msg.params.content_changes.last.text
  end
  
  # When a text document is closed, remove it from our local set.
  def handle(msg : LSP::Message::DidClose)
    @open_files.delete(msg.params.text_document.uri)
  end
  
  # When a text document is saved, do nothing.
  def handle(msg : LSP::Message::DidSave)
    # Ignore.
  end
  
  # TODO: Proper hover support.
  def handle(msg : LSP::Message::Hover)
    pos = msg.params.position
    text = @open_files[msg.params.text_document.uri]? || ""
    
    raise NotImplementedError.new("not a file") \
      if msg.params.text_document.uri.scheme != "file"
    
    filename = msg.params.text_document.uri.path.not_nil!
    # TODO: Don't hard-code this.
    if filename.starts_with?("/home/jemc/1/code/hg/mare/src/prelude")
      filename = filename.sub("/home/jemc/1/code/hg/mare/src/prelude",
        "/opt/mare/src/prelude")
    elsif filename.starts_with?("/home/jemc/1/code/hg/mare/tmp")
      filename = filename.sub("/home/jemc/1/code/hg/mare/tmp", "/opt/code")
    end
    
    dirname = File.dirname(filename)
    sources = Compiler.get_library_sources(dirname)
    
    source = sources.find { |s| s.path == filename }.not_nil!
    source_pos = Source::Pos.point(source, pos.line.to_i32, pos.character.to_i32)
    
    # TODO: Don't compile from scratch on each hover call.
    info, info_pos =
      Compiler.compile(sources, :serve_hover).serve_hover[source_pos]
    
    info << "(no hover information)" if info.empty?
    
    @wire.respond msg do |msg|
      msg.result.contents.kind = "plaintext"
      msg.result.contents.value = info.join("\n\n")
      msg.result.range = LSP::Data::Range.new(
        LSP::Data::Position.new(info_pos.row.to_i64, info_pos.col.to_i64),
        LSP::Data::Position.new(info_pos.row.to_i64, info_pos.col.to_i64 + info_pos.size), # TODO: account for spilling over into a new row
      )
      msg
    end
  end
  
  # TODO: Proper completion support.
  def handle(req : LSP::Message::Completion)
    pos = req.params.position
    text = @open_files[req.params.text_document.uri]? || ""
    
    @wire.respond req do |msg|
      case req.params.context.try(&.trigger_kind)
      when LSP::Data::CompletionTriggerKind::TriggerCharacter
        case req.params.context.not_nil!.trigger_character
        when ":"
          # Proceed with a ":"-based completion if the line is otherwise empty.
          line_text = text.split("\n")[pos.line]
          if line_text =~ /\A\s*:\s*\z/
            msg.result.items =
              ["class", "prop", "fun"].map do |label|
                LSP::Data::CompletionItem.new.try do |item|
                  item.label = label
                  item.kind = LSP::Data::CompletionItemKind::Method
                  item.detail = "declare a #{label}"
                  item.documentation = LSP::Data::MarkupContent.new "markdown",
                    "# TODO: Completion\n`#{pos.to_json}`\n```ruby\n#{text}\n```\n"
                  
                  if @use_snippet_completions
                    item.insert_text_format = LSP::Data::InsertTextFormat::Snippet
                    new_text = "#{label}${1| , ref , val , iso , box , trn , tag , non |}${2:Name}\n  $0"
                  else
                    new_text = "#{label} "
                  end
                  
                  item.text_edit = LSP::Data::TextEdit.new(
                    LSP::Data::Range.new(pos, pos),
                    new_text,
                  )
                  
                  item
                end
              end
          end
        end
      end
      msg
    end
  end
  
  # All other messages are unhandled - just print them for debugging purposes.
  def handle(msg)
    @stderr.puts "Unhandled incoming message!"
    @stderr.puts msg.to_json
  end
end
