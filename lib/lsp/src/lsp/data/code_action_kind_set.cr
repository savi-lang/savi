require "json"

module LSP::Data
  struct CodeActionKindSet
    include JSON::Serializable

    # The code action kind values the client supports. When this
    # property exists the client also guarantees that it will
    # handle values outside its set gracefully and falls back
    # to a default value when unknown.
    @[JSON::Field(key: "valueSet")]
    property value_set : Array(String) = [] of String

    def initialize
      @value_set = [] of String
    end
  end
end
