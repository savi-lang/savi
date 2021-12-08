require "lsp"
require "uri"

class Savi::Server
  def initialize(
    @stdin : IO = STDIN,
    @stdout : IO = STDOUT,
    @stderr : IO = STDERR
  )
    @wire = LSP::Wire.new(@stdin, @stdout)
    @compiled = false
    @ctx = nil.as Compiler::Context?

    @use_snippet_completions = false
  end

  def run
    setup
    loop { handle @wire.receive }
  end

  def setup
    @stderr.puts("LSP Server is starting...")

    # TODO: Remove legacy env var names not prefixed by "SAVI_".
    Savi.compiler.source_service.standard_directory_remap = (
      ENV["SAVI_STANDARD_DIRECTORY_REMAP"]? || ENV["STD_DIRECTORY_MAPPING"]?
    ).try(&.split2!(':'))
    Savi.compiler.source_service.main_directory_remap = (
      ENV["SAVI_MAIN_DIRECTORY_REMAP"]? || ENV["SOURCE_DIRECTORY_MAPPING"]?
    ).try(&.split2!(':'))

    # Copy standard package into the standard remap directory, if provided.
    # Set that destination directory as being the canonical standard package,
    # when the standard package is referenced during compilation.
    Savi.compiler.source_service.standard_directory_remap.try { |_, dest_path|
      # TODO: handle process errors here, probably via a cleaner abstraction.
      Process.run("cp", ["-r",
        File.join(
          Savi.compiler.source_service.standard_package_internal_path,
          ".",
        ),
        dest_path,
      ])
      Savi.compiler.source_service.standard_package_internal_path = dest_path
    }

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
      msg.result.capabilities.definition_provider = true
      msg.result.capabilities.completion_provider =
        LSP::Data::ServerCapabilities::CompletionOptions.new(false, [":"])
      msg.result.capabilities.document_formatting_provider = true
      msg.result.capabilities.document_range_formatting_provider = true
      msg.result.capabilities.document_on_type_formatting_provider =
        LSP::Data::ServerCapabilities::DocumentOnTypeFormattingOptions.new(
          "\n", ")", "]"
        )
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

  # When a text document is opened, store it in our source overrides.
  def handle(msg : LSP::Message::DidOpen)
    text = msg.params.text_document.text
    path = msg.params.text_document.uri.path
    Savi.compiler.source_service.set_source_override(path, text)

    send_diagnostics(msg.params.text_document.uri.path.not_nil!, text)
  end

  # When a text document is changed, update it in our source overrides.
  def handle(msg : LSP::Message::DidChange)
    text = msg.params.content_changes.last.text
    path = msg.params.text_document.uri.path
    Savi.compiler.source_service.set_source_override(path, text)

    @ctx = nil
    send_diagnostics(msg.params.text_document.uri.path.not_nil!, text)
  end

  # When a text document is closed, remove it from our source overrides.
  def handle(msg : LSP::Message::DidClose)
    path = msg.params.text_document.uri.path
    Savi.compiler.source_service.unset_source_override(path)
  end

  # When a text document is saved, do nothing.
  def handle(msg : LSP::Message::DidSave)
    @ctx = nil

    send_diagnostics(msg.params.text_document.uri.path.not_nil!)
  end

  # TODO: Get Hover working again, in the presence of package manifests.
  def handle(msg : LSP::Message::Hover)
    pos = msg.params.position
    filename = msg.params.text_document.uri.path.not_nil!
    dirname = File.dirname(filename)
    sources = Savi.compiler.source_service.get_manifest_sources_at_or_above(dirname)
    options = Compiler::Options.new

    # source = sources.find { |s| s.path == filename }.not_nil!
    # source_pos = Source::Pos.point(source, pos.line.to_i32, pos.character.to_i32)

    info = [] of String
    # begin
    #   if @ctx.nil?
    #     @ctx = Savi.compiler.compile(sources, :serve_lsp, options)
    #   end
    #   ctx = @ctx.not_nil!

    #   info, info_pos =
    #     ctx.serve_hover[source_pos]
    # rescue
    # end

    info << "(no hover information)" if info.empty?

    @wire.respond msg do |msg|
      msg.result.contents.kind = "plaintext"
      msg.result.contents.value = info.join("\n\n")
      # if info_pos.is_a?(Savi::Source::Pos)
      #   msg.result.range = info_pos.to_lsp_range
      # end
      msg
    end
  end

  def handle(req : LSP::Message::Formatting)
    filename = req.params.text_document.uri.path.not_nil!
    dirname = File.dirname(filename)
    sources = Savi.compiler.source_service.get_directory_sources(dirname)
    options = Savi::Compiler::Options.new
    options.skip_manifest = true

    ctx = Savi.compiler.compile(sources, :format, options)
    doc = ctx.root_docs.find(&.pos.source.path.==(filename)).not_nil!

    edits = AST::Format.run(ctx, ctx.root_package_link, [doc]).flat_map(&.last)

    @wire.respond(req) { |msg|
      msg.result = edits.map { |edit|
        LSP::Data::TextEdit.new(
          edit.pos.to_lsp_range,
          edit.replacement,
        )
      }
      msg
    }
  end

  def handle(req : LSP::Message::RangeFormatting)
    filename = req.params.text_document.uri.path.not_nil!
    dirname = File.dirname(filename)
    sources = Savi.compiler.source_service.get_directory_sources(dirname)
    options = Savi::Compiler::Options.new
    options.skip_manifest = true

    ctx = Savi.compiler.compile(sources, :format, options)
    doc = ctx.root_docs.find(&.pos.source.path.==(filename)).not_nil!

    edits = AST::Format.run(ctx, ctx.root_package_link, [doc]).flat_map(&.last)

    # Only select edits within the intended range.
    range = Source::Pos.from_lsp_range(doc.pos.source, req.params.range)
    edits.select! { |edit| range.contains?(edit.pos) }

    @wire.respond(req) { |msg|
      msg.result = edits.map { |edit|
        LSP::Data::TextEdit.new(edit.pos.to_lsp_range, edit.replacement)
      }
      msg
    }
  end

  def handle(req : LSP::Message::OnTypeFormatting)
    filename = req.params.text_document.uri.path.not_nil!
    dirname = File.dirname(filename)
    sources = Savi.compiler.source_service.get_directory_sources(dirname)
    options = Savi::Compiler::Options.new
    options.skip_manifest = true

    ctx = Savi.compiler.compile(sources, :format, options)
    doc = ctx.root_docs.find(&.pos.source.path.==(filename)).not_nil!

    edits = AST::Format.run(ctx, ctx.root_package_link, [doc]).flat_map(&.last)

    @wire.respond(req) { |msg|
      msg.result = edits.map { |edit|
        LSP::Data::TextEdit.new(edit.pos.to_lsp_range, edit.replacement)
      }
      msg
    }
  end

  # TODO: Proper completion support.
  def handle(req : LSP::Message::Completion)
    pos = req.params.position
    path = req.params.text_document.uri.path
    source = Savi.compiler.source_service.get_source_at(path)
    text = source.content

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
                    new_text = "#{label}${1| , ref , val , iso , box , tag , non |}${2:Name}\n  $0"
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
        else
        end
      else
      end
      msg
    end
  end

  # All other messages are unhandled - just print them for debugging purposes.
  def handle(msg)
    @stderr.puts "Unhandled incoming message!"
    @stderr.puts msg.to_json
  end

  def send_diagnostics(filename : String, content : String? = nil)
    dirname = File.dirname(filename)
    sources = Savi.compiler.source_service.get_manifest_sources_at_or_above(dirname)
    options = Compiler::Options.new

    ctx = Savi.compiler.compile(sources, :serve_errors, options)

    @wire.notify(LSP::Message::PublishDiagnostics) do |msg|
      msg.params.uri = URI.new(path: filename)
      msg.params.diagnostics = ctx.errors.map(&.to_lsp_diagnostic)

      msg
    end

  # Catch an Error if it happens here at the top level.
  rescue err : Error
    @wire.notify(LSP::Message::PublishDiagnostics) do |msg|
      msg.params.uri = URI.new(path: filename)
      msg.params.diagnostics = [err.to_lsp_diagnostic]

      msg
    end
  end
end
