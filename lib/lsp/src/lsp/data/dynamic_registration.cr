require "json"

module LSP::Data
  struct DynamicRegistration
    include JSON::Serializable

    # The capability includes dynamic registration.
    @[JSON::Field(key: "dynamicRegistration")]
    property dynamic_registration : Bool = false

    def initialize
      @dynamic_registration = false
    end
  end
end
