require "json"

module LSP::Data
  struct Range
    JSON.mapping({
      start: Position,
      finish: {type: Position, key: "end"},
    })
    def initialize(
      @start = Position.new,
      @finish = Position.new)
    end
  end
end
