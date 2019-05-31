require "json"

module LSP::Data
  struct TextDocumentContentChangeEvent
    JSON.mapping({
      # The range of the document that changed.
      range: Range?,
      
      # The length of the range that got replaced.
      range_length: {type: Int64?, key: "rangeLength"},
      
      # The new text of the range/document.
      text: String,
    })
    def initialize(
      @range = nil,
      @range_length = nil,
      @text = "")
    end
  end
end
