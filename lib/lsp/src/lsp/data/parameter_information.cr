require "json"

module LSP::Data
  struct ParameterInformation
    JSON.mapping({
      # The label of this parameter. Will be shown in the UI.
      label: String,

      # The human-readable doc-comment of this parameter.
      # Will be shown in the UI but can be omitted.
      documentation: String | MarkupContent | Nil,
    })
    def initialize(
      @label = "",
      @documentation = nil)
    end
  end
end
