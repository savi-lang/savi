require "json"

module LSP::Data
  struct Diagnostic
    include JSON::Serializable

    # The range at which the message applies.
    property range : Range

    # The diagnostic's severity. Can be omitted. If omitted it is up to the
    # client to interpret diagnostics as error, warning, info or hint.
    @[JSON::Field(converter: Enum::ValueConverter(LSP::Data::Diagnostic::Severity))]
    property severity : Severity?

    # The diagnostic's code, which might appear in the user interface.
    property code : Int64 | String | Nil

    # A human-readable string describing the source of this
    # diagnostic, e.g. 'typescript' or 'super lint'.
    property source : String?

    # The diagnostic's message.
    property message : String

    # An array of related diagnostic information, e.g. when symbol-names within
    # a scope collide all definitions can be marked via this property.
    @[JSON::Field(key: "relatedInformation")]
    property related_information : Array(RelatedInformation) = [] of RelatedInformation

    def initialize(
      @range = Range.new,
      @severity = Severity::Error,
      @code = nil,
      @source = nil,
      @message = "",
      @related_information = [] of RelatedInformation
    )
    end

    enum Severity
      Error       = 1
      Warning     = 2
      Information = 3
      Hint        = 4

      def self.new(*args)
        ::Enum::ValueConverter(Severity).from_json(*args)
      end

      def to_json(*args)
        ::Enum::ValueConverter(Severity).to_json(self, *args)
      end
    end

    # Represents a related message and source code location for a diagnostic.
    # This should be used to point to code locations that cause or related to
    # a diagnostics, e.g when duplicating a symbol in a scope.
    struct RelatedInformation
      include JSON::Serializable
      # The location of this related diagnostic information.
      property location : Location

      # The message of this related diagnostic information.
      property message : String

      def initialize(@location = Location.new, @message = "")
      end
    end
  end
end
