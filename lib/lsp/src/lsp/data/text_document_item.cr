require "json"

module LSP::Data
  struct TextDocumentItem
    include JSON::Serializable

    # The text document's URI.
    @[JSON::Field(converter: LSP::JSONUtil::URIString)]
    property uri : URI

    # The text document's language identifier.
    @[JSON::Field(key: "languageId")]
    property language_id : String

    # The version number of this document (it will increase after each
    # change, including undo/redo).
    property version : Int64

    # The content of the opened text document.
    property text : String

    def initialize(
      @uri = URI.new,
      @language_id = "",
      @version = 0,
      @text = ""
    )
    end
  end
end
