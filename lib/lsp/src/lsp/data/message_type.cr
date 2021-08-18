require "json"

module LSP::Data
  enum MessageType
    Error   = 1
    Warning = 2
    Info    = 3
    Log     = 4

    def self.new(*args)
      ::Enum::ValueConverter(MessageType).from_json(*args)
    end

    def to_json(*args)
      ::Enum::ValueConverter(MessageType).to_json(self, *args)
    end
  end
end
