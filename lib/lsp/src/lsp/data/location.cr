require "json"

module LSP::Data
  struct Location
    include JSON::Serializable

    @[JSON::Field(converter: LSP::JSONUtil::URIString)]
    property uri : URI

    property range : Range

    def initialize(
      @uri = URI.new,
      @range = Range.new
    )
    end
  end
end
