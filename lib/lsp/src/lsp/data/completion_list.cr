require "json"

module LSP::Data
  # Represents a collection of [completion items](#CompletionItem) to be
  # presented in the editor.
  struct CompletionList
    include JSON::Serializable

    # This list it not complete. Further typing should result in recomputing
    # this list.
    @[JSON::Field(key: "isIncomplete")]
    property is_incomplete : Bool

    # The completion items.
    property items : Array(CompletionItem)

    def initialize(
      @is_incomplete = false,
      @items = [] of CompletionItem
    )
    end
  end
end
