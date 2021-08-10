require "json"

module LSP::Data
  # Represents a collection of [completion items](#CompletionItem) to be
  # presented in the editor.
  struct CompletionList
    JSON.mapping({
      # This list it not complete. Further typing should result in recomputing
      # this list.
      is_incomplete: {type: Bool, key: "isIncomplete"},

      # The completion items.
      items: Array(CompletionItem),
    })
    def initialize(
      @is_incomplete = false,
      @items = [] of CompletionItem)
    end
  end
end
