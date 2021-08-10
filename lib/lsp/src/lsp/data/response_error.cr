require "json"

module LSP::Data
  struct ResponseError(D)
    include JSON::Serializable

    property code : Code
    property message : String
    property data : D?

    enum Code
      # Defined by JSON RPC.
      ParseError           = -32700
      InvalidRequest       = -32600
      MethodNotFound       = -32601
      InvalidParams        = -32602
      InternalError        = -32603
      ServerErrorStart     = -32099
      ServerErrorEnd       = -32000
      ServerNotInitialized = -32002
      UnknownErrorCode     = -32001

      # Defined by the protocol.
      RequestCancelled = -32800

      def self.new(*args)
        ::Enum::ValueConverter(Code).from_json(*args)
      end

      def to_json(*args)
        ::Enum::ValueConverter(Code).to_json(self, *args)
      end
    end

    def initialize(
      @data = nil,
      @message = "(no error message specified)",
      @code = Code::InternalError
    )
    end
  end
end
