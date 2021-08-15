require "json"

module LSP::Data
  enum TextDocumentSaveReason
    # Manually triggered, e.g. by the user pressing save, by starting debugging,
    # or by an API call.
    Manual = 1

    # Automatic after a delay.
    AfterDelay = 2

    # When the editor lost focus.
    FocusOut = 3

    def self.new(*args)
      ::Enum::ValueConverter(TextDocumentSaveReason).from_json(*args)
    end

    def to_json(*args)
      ::Enum::ValueConverter(TextDocumentSaveReason).to_json(self, *args)
    end
  end
end
