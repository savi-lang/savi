require "json"

module LSP::Data
  struct TextDocumentVersionedIdentifier
    include JSON::Serializable

    # The text document's URI.
    @[JSON::Field(converter: LSP::JSONUtil::URIString)]
    property uri : URI

    # The version number of this document (it will increase after each
    # change, including undo/redo).
    property version : Int64

    def initialize(@uri = URI.new, @version = 0)
    end
  end
end
