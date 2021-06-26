require "json"

module LSP::Data
  struct ParameterInformation
    include JSON::Serializable

    # The label of this parameter. Will be shown in the UI.
    property label : String

    # The human-readable doc-comment of this parameter.
    # Will be shown in the UI but can be omitted.
    property documentation : String | MarkupContent | Nil

    def initialize(
      @label = "",
      @documentation = nil
    )
    end
  end
end
