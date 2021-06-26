require "json"

module LSP::Data
  # A textual edit applicable to a text document.
  struct TextEdit
    include JSON::Serializable

    # The range of the text document to be manipulated.
    # To insert text into a document create a range where start === end.
    property range : Range

    # The string to be inserted.
    # For delete operations use an empty string.
    @[JSON::Field(key: "newText")]
    property new_text : String

    def initialize(
      @range = Range.new,
      @new_text = ""
    )
    end
  end
end
