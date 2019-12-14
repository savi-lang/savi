require "json"

module LSP::Data
  # Contains additional information about the context in which a completion
  # request is triggered.
  struct CompletionContext
    JSON.mapping({
      # How the completion was triggered.
      trigger_kind: {type: CompletionTriggerKind, key: "triggerKind"},

      # The trigger character (a single character) that has trigger code
      # complete. Is undefined if
      # `triggerKind !== CompletionTriggerKind.TriggerCharacter`
      trigger_character: {type: String?, key: "triggerCharacter"},
    })
    def initialize(
      @trigger_kind = CompletionTriggerKind::Invoked,
      @trigger_character = nil)
    end
  end
end
