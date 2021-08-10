require "json"

module LSP::Data
  struct TextDocumentIdentifier
    JSON.mapping({
      # The text document's URI.
      uri: {type: URI, converter: JSONUtil::URIString},
    })
    def initialize(@uri = URI.new)
    end
  end
end
