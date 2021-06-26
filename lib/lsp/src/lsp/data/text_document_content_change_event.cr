require "json"

module LSP::Data
  struct TextDocumentContentChangeEvent
    include JSON::Serializable

    # The range of the document that changed.
    property range : Range?

    # The length of the range that got replaced.
    @[JSON::Field(key: "rangeLength")]
    property range_length : Int64?

    # The new text of the range/document.
    property text : String

    def initialize(
      @range = nil,
      @range_length = nil,
      @text = ""
    )
    end
  end
end
