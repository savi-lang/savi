require "json"

module LSP::Data
  struct SymbolKindSet
    include JSON::Serializable

    # The symbol kind values the client supports. When this
    # property exists the client also guarantees that it will
    # handle values outside its set gracefully and falls back
    # to a default value when unknown.
    #
    # If this property is not present the client only supports
    # the symbol kinds from `File` to `Array` as defined in
    # the initial version of the protocol.
    @[JSON::Field(key: "valueSet")]
    property value_set : Array(SymbolKind) = SymbolKind.default

    def initialize
      @value_set = SymbolKind.default
    end
  end
end
