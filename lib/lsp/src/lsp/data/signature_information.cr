require "json"

module LSP::Data
  struct SignatureInformation
    include JSON::Serializable

    # The label of this signature. Will be shown in the UI.
    property label : String

    # The human-readable doc-comment of this signature.
    # Will be shown in the UI but can be omitted.
    property documentation : String | MarkupContent | Nil

    # The parameters of this signature.
    property parameters : Array(ParameterInformation) = [] of ParameterInformation

    def initialize(
      @label = "",
      @documentation = nil,
      @parameters = [] of ParameterInformation
    )
    end
  end
end
