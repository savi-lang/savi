require "json"

module LSP::Data
  struct CompletionItemKindSet
    JSON.mapping({
      # The completion item kind values the client supports. When this
      # property exists the client also guarantees that it will
      # handle values outside its set gracefully and falls back
      # to a default value when unknown.
      #
      # If this property is not present the client only supports
      # the completion items kinds from `Text` to `Reference` as defined in
      # the initial version of the protocol.
      value_set: {
        type: Array(CompletionItemKind),
        default: CompletionItemKind.default,
        key: "valueSet",
      },
    })
    def initialize
      @value_set = CompletionItemKind.default
    end
  end
end
