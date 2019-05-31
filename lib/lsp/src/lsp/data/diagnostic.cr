require "json"

module LSP::Data
  struct Diagnostic
    JSON.mapping({
      # The range at which the message applies.
      range: Range,
      
      # The diagnostic's severity. Can be omitted. If omitted it is up to the
      # client to interpret diagnostics as error, warning, info or hint.
      severity: Severity?,
      
      # The diagnostic's code, which might appear in the user interface.
      code: Int64 | String | Nil,
      
      # A human-readable string describing the source of this
      # diagnostic, e.g. 'typescript' or 'super lint'.
      source: String?,
      
      # The diagnostic's message.
      message: String,
      
      # An array of related diagnostic information, e.g. when symbol-names within
      # a scope collide all definitions can be marked via this property.
      related_information: {
        type: Array(RelatedInformation),
        default: [] of RelatedInformation,
        key: "relatedInformation",
      },
    })
    def initialize(
      @range = Range.new,
      @severity = Severity::Error,
      @code = nil,
      @source = nil,
      @message = "",
      @related_information = [] of RelatedInformation)
    end
    
    enum Severity
      Error       = 1
      Warning     = 2
      Information = 3
      Hint        = 4
    end
    
    # Represents a related message and source code location for a diagnostic.
    # This should be used to point to code locations that cause or related to
    # a diagnostics, e.g when duplicating a symbol in a scope.
    struct RelatedInformation
      JSON.mapping({
        # The location of this related diagnostic information.
        location: Location,
        
        # The message of this related diagnostic information.
        message: String,
      })
      def initialize(@location = Location.new, @message = "")
      end
    end
  end
end
