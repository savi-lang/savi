require "json"

module LSP::Data
  # Defines how the host (editor) should sync document changes to the language server.
  enum TextDocumentSyncKind
    # Documents should not be synced at all.
    None = 0

    # Documents are synced by always sending the full content
    # of the document.
    Full = 1

    # Documents are synced by sending the full content on open.
    # After that only incremental updates to the document are
    # send.
    Incremental = 2

    def self.new(*args)
      ::Enum::ValueConverter(TextDocumentSyncKind).from_json(*args)
    end

    def to_json(*args)
      ::Enum::ValueConverter(TextDocumentSyncKind).to_json(self, *args)
    end
  end
end
