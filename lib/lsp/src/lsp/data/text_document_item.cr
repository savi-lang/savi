require "json"

module LSP::Data
  struct TextDocumentItem
    JSON.mapping({
      # The text document's URI.
      uri: {type: URI, converter: JSONUtil::URIString},

      # The text document's language identifier.
      language_id: {type: String, key: "languageId"},

      # The version number of this document (it will increase after each
      # change, including undo/redo).
      version: Int64,

      # The content of the opened text document.
      text: String,
    })
    def initialize(
      @uri = URI.new,
      @language_id = "",
      @version = 0,
      @text = "")
    end
  end
end
