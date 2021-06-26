require "json"

module LSP::Data
  struct TextDocumentIdentifier
    include JSON::Serializable

    # The text document's URI.
    @[JSON::Field(converter: LSP::JSONUtil::URIString)]
    property uri : URI

    def initialize(@uri = URI.new)
    end
  end
end
