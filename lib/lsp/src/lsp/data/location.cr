require "json"

module LSP::Data
  struct Location
    JSON.mapping({
      uri: {type: URI, converter: JSONUtil::URIString},
      range: Range,
    })
    def initialize(
      @uri = URI.new,
      @range = Range.new)
    end
  end
end
