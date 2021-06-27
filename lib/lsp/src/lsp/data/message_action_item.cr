require "json"

module LSP::Data
  struct MessageActionItem
    include JSON::Serializable

    # A short title like 'Retry', 'Open Log' etc.
    property title : String

    def initialize(@title)
    end
  end
end
