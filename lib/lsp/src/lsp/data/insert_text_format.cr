require "json"

module LSP::Data
  # Defines whether the insert text in a completion item should be interpreted
  # as plain text or a snippet.
  enum InsertTextFormat
    # The primary text to be inserted is treated as a plain string.
    PlainText = 1

    # The primary text to be inserted is treated as a snippet.
    #
    # A snippet can define tab stops and placeholders with `$1`, `$2`
    # and `${3:foo}`. `$0` defines the final tab stop, it defaults to
    # the end of the snippet. Placeholders with equal identifiers are linked,
    # that is typing in one will update others too.
    Snippet = 2

    def self.new(*args)
      ::Enum::ValueConverter(InsertTextFormat).from_json(*args)
    end

    def to_json(*args)
      ::Enum::ValueConverter(InsertTextFormat).to_json(self, *args)
    end
  end
end
