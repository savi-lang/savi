require "json"

module LSP::Data
  # Contains additional information about the context in which a completion
  # request is triggered.
  struct CompletionContext
    include JSON::Serializable

    # How the completion was triggered.
    @[JSON::Field(key: "triggerKind", converter: Enum::ValueConverter(LSP::Data::CompletionTriggerKind))]
    property trigger_kind : CompletionTriggerKind

    # The trigger character (a single character) that has trigger code
    # complete. Is undefined if
    # `triggerKind !== CompletionTriggerKind.TriggerCharacter`
    @[JSON::Field(key: "triggerCharacter")]
    property trigger_character : String?

    def initialize(
      @trigger_kind = CompletionTriggerKind::Invoked,
      @trigger_character = nil
    )
    end
  end
end
