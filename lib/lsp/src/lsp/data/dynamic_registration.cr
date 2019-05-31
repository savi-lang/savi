require "json"

module LSP::Data
  struct DynamicRegistration
    JSON.mapping({
      # The capability includes dynamic registration.
      dynamic_registration: {
        type: Bool,
        default: false,
        key: "dynamicRegistration"
      },
    })
    def initialize
      @dynamic_registration = false
    end
  end
end
