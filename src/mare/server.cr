require "lsp"
require "uri"

class Mare::Server
  def initialize(
    @stdin : IO = STDIN,
    @stdout : IO = STDOUT,
    @stderr : IO = STDERR)
    @wire = LSP::Wire.new(@stdin, @stdout)
    @open_files = {} of URI => String
    @compiled = false
    @ctx = nil.as Mare::Compiler::Context?
    @workspace = ""

    @use_snippet_completions = false
  end

  def run
    setup
    loop { handle @wire.receive }
  end

  def setup
    @stderr.puts("LSP Server is starting...")

    ENV["STD_DIRECTORY_MAPPING"]?.try do |mapping|
      mapping.split(":").each_slice 2 do |pair|
        next unless pair.size == 2
        host_path = pair[0]
        dest_path = pair[1]

        @stderr.puts(Process.run("cp", [Compiler::STANDARD_LIBRARY_DIRNAME, dest_path, "-r"]).exit_code)
        @stderr.puts(Process.run("cp", [Compiler.prelude_library_path, dest_path, "-r"]).exit_code)
      end
    end

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

    @workspace = msg.params.workspace_folders[0].uri.path.not_nil!

    @wire.respond msg do |msg|
      msg.result.capabilities.text_document_sync.open_close = true
      msg.result.capabilities.text_document_sync.change =
        LSP::Data::TextDocumentSyncKind::Full
      msg.result.capabilities.hover_provider = true
      msg.result.capabilities.definition_provider = true
      msg.result.capabilities.completion_provider =
        LSP::Data::ServerCapabilities::CompletionOptions.new(false, [":"])
      msg
    end
  end

  # When told that we're free to be initialized, do so.
  def handle(msg : LSP::Message::Initialized)
    # TODO: Start server resources.
  end

  # When told that we're free to be initialized, do so.
  def handle(msg : LSP::Message::DidChangeConfiguration)
    @stderr.puts(msg)
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
    @ctx = nil
  end

  # When a text document is closed, remove it from our local set.
  def handle(msg : LSP::Message::DidClose)
    @open_files.delete(msg.params.text_document.uri)
  end

  # When a text document is saved, do nothing.
  def handle(msg : LSP::Message::DidSave)
    # Ignore.
    @ctx = nil
  end

  def handle(msg : LSP::Message::Definition)
    pos = msg.params.position
    text = @open_files[msg.params.text_document.uri]? || ""

    raise NotImplementedError.new("not a file") \
      if msg.params.text_document.uri.scheme != "file"

    host_filename = msg.params.text_document.uri.path.not_nil!
    filename = msg.params.text_document.uri.path.not_nil!

    # If we're running in a docker container, or in some other remote
    # environment, the host's source path may not match ours, and we
    # can apply the needed transformation as specified in this ENV var.
    ENV["STD_DIRECTORY_MAPPING"]?.try do |mapping|
      mapping.split(":").each_slice 2 do |pair|
        next unless pair.size == 2
        host_path = pair[0]
        dest_path = pair[1]

        if filename.starts_with?(host_path)
          filename = 
            if filename.includes?("prelude")
              tmp_fname = filename.sub(host_path, Compiler.prelude_library_path)
              tmp_fname.sub("prelude/prelude", "prelude")
            else
              filename.sub(host_path, Compiler::STANDARD_LIBRARY_DIRNAME)
            end
        end
      end
    end
    ENV["SOURCE_DIRECTORY_MAPPING"]?.try do |mapping|
      mapping.split(":").each_slice 2 do |pair|
        next unless pair.size == 2
        host_path = pair[0]
        dest_path = pair[1]

        if filename.starts_with?(host_path)
          filename = filename.sub(host_path, dest_path)
        end
      end
    end

    dirname = File.dirname(filename)
    sources = Compiler.get_library_sources(dirname)

    source = sources.find { |s| s.path == filename }.not_nil!
    source_pos = Source::Pos.point(source, pos.line.to_i32, pos.character.to_i32)

    if @ctx.nil?
      @ctx = Compiler.compile(sources, :serve_lsp)
    end
    ctx = @ctx.not_nil!

    begin
      definition_pos = ctx.serve_definition[source_pos]
    rescue
    end

    if definition_pos.is_a? Mare::Source::Pos
      user_filepath = definition_pos.source.path 

      ENV["STD_DIRECTORY_MAPPING"]?.try do |mapping|
        mapping.split(":").each_slice 2 do |pair|
          next unless pair.size == 2
          host_path = pair[0]
          dest_path = pair[1]

          if user_filepath.starts_with?(Compiler.prelude_library_path)
            user_filepath = user_filepath.sub(Compiler.prelude_library_path, File.join(host_path, "prelude"))
          end

          if user_filepath.starts_with?(Compiler::STANDARD_LIBRARY_DIRNAME)
            user_filepath = user_filepath.sub(Compiler::STANDARD_LIBRARY_DIRNAME, host_path)
          end
        end
      end
      ENV["SOURCE_DIRECTORY_MAPPING"]?.try do |mapping|
        mapping.split(":").each_slice 2 do |pair|
          next unless pair.size == 2
          host_path = pair[0]
          dest_path = pair[1]

          if user_filepath.starts_with?(dest_path)
            user_filepath = user_filepath.sub(dest_path, host_path)
          end
        end
      end

      @wire.respond msg do |msg|
        msg.result = LSP::Data::Location.new(
          URI.new(path: user_filepath),
          LSP::Data::Range.new(
            LSP::Data::Position.new(
              definition_pos.row.to_i64,
              definition_pos.col.to_i64,
            ),
            LSP::Data::Position.new(
              definition_pos.row.to_i64,
              definition_pos.col.to_i64 + (definition_pos.finish - definition_pos.start),
            ),
          ),
        )
        msg
      end
    else
      @wire.error_respond msg do |msg|
        msg
      end
    end
  end

  def handle(msg : LSP::Message::Hover)
    pos = msg.params.position
    text = @open_files[msg.params.text_document.uri]? || ""

    raise NotImplementedError.new("not a file") \
      if msg.params.text_document.uri.scheme != "file"

    filename = msg.params.text_document.uri.path.not_nil!

    # If we're running in a docker container, or in some other remote
    # environment, the host's source path may not match ours, and we
    # can apply the needed transformation as specified in this ENV var.
    ENV["STD_DIRECTORY_MAPPING"]?.try do |mapping|
      mapping.split(":").each_slice 2 do |pair|
        next unless pair.size == 2
        host_path = pair[0]
        dest_path = pair[1]

        if filename.starts_with?(host_path)
          filename = 
            if filename.includes?("prelude")
              tmp_fname = filename.sub(host_path, Compiler.prelude_library_path)
              tmp_fname.sub("prelude/prelude", "prelude")
            else
              filename.sub(host_path, Compiler::STANDARD_LIBRARY_DIRNAME)
            end
        end
      end
    end
    ENV["SOURCE_DIRECTORY_MAPPING"]?.try do |mapping|
      mapping.split(":").each_slice 2 do |pair|
        next unless pair.size == 2
        host_path = pair[0]
        dest_path = pair[1]

        if filename.starts_with?(host_path)
          filename = filename.sub(host_path, dest_path)
        end
      end
    end

    dirname = File.dirname(filename)
    sources = Compiler.get_library_sources(dirname)

    source = sources.find { |s| s.path == filename }.not_nil!
    source_pos = Source::Pos.point(source, pos.line.to_i32, pos.character.to_i32)

    info = [] of String
    begin
      if @ctx.nil?
        @ctx = Compiler.compile(sources, :serve_lsp)
      end
      ctx = @ctx.not_nil!

      info, info_pos =
        ctx.serve_hover[source_pos]
    rescue
    end

    info << "(no hover information)" if info.empty?

    @wire.respond msg do |msg|
      msg.result.contents.kind = "plaintext"
      msg.result.contents.value = info.join("\n\n")
      if info_pos.is_a?(Mare::Source::Pos)
        msg.result.range = LSP::Data::Range.new(
          LSP::Data::Position.new(info_pos.row.to_i64, info_pos.col.to_i64),
          LSP::Data::Position.new(info_pos.row.to_i64, info_pos.col.to_i64 + info_pos.size), # TODO: account for spilling over into a new row
        )
      end
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
