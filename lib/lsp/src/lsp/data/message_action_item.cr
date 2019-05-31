require "json"

module LSP::Data
  struct MessageActionItem
    JSON.mapping({
      # A short title like 'Retry', 'Open Log' etc.
      title: String,
    })
    def initialize(@title)
    end
  end
end
