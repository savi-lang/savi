require "json"

module LSP::Data
  struct Range
    include JSON::Serializable

    property start : Position

    @[JSON::Field(key: "end")]
    property finish : Position

    def initialize(
      @start = Position.new,
      @finish = Position.new
    )
    end
  end
end
