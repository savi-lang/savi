require "json"

module LSP::Data
  struct CodeActionKindSet
    JSON.mapping({
      # The code action kind values the client supports. When this
      # property exists the client also guarantees that it will
      # handle values outside its set gracefully and falls back
      # to a default value when unknown.
      value_set: {
        type: Array(String),
        default: [] of String,
        key: "valueSet",
      },
    })
    def initialize
      @value_set = [] of String
    end
  end
end
