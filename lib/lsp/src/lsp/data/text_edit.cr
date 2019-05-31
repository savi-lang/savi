require "json"

module LSP::Data
  # A textual edit applicable to a text document.
  struct TextEdit
    JSON.mapping({
      # The range of the text document to be manipulated.
      # To insert text into a document create a range where start === end.
      range: Range,
      
      # The string to be inserted.
      # For delete operations use an empty string.
      new_text: {type: String, key: "newText"},
    })
    def initialize(
      @range = Range.new,
      @new_text = "")
    end
  end
end
