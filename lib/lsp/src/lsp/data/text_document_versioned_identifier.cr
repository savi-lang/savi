require "json"

module LSP::Data
  struct TextDocumentVersionedIdentifier
    JSON.mapping({
      # The text document's URI.
      uri: {type: URI, converter: JSONUtil::URIString},
      
      # The version number of this document (it will increase after each
      # change, including undo/redo).
      version: Int64,
    })
    def initialize(@uri = URI.new, @version = 0)
    end
  end
end
