require "json"

module LSP::Data
  struct SignatureInformation
    JSON.mapping({
      # The label of this signature. Will be shown in the UI.
      label: String,
      
      # The human-readable doc-comment of this signature.
      # Will be shown in the UI but can be omitted.
      documentation: String | MarkupContent | Nil,
      
      # The parameters of this signature.
      parameters: {
        type: Array(ParameterInformation),
        default: [] of ParameterInformation,
      },
    })
    def initialize(
      @label = "",
      @documentation = nil,
      @parameters = [] of ParameterInformation)
    end
  end
end
