require "json"

module LSP::Data
  # ClientCapabilities now define capabilities for dynamic registration,
  # workspace and text document features the client supports. The experimental
  # can be used to pass experimental capabilities under development. For
  # future compatibility a ClientCapabilities object literal can have more
  # properties set than currently defined. Servers receiving a
  # ClientCapabilities object literal with unknown properties should ignore
  # these properties. A missing property should be interpreted as an absence
  # of the capability. If a property is missing that defines sub properties
  # all sub properties should be interpreted as an absence of the capability.
  #
  # Client capabilities got introduced with version 3.0 of the protocol.
  # They therefore only describe capabilities that got introduced in 3.x
  # or later. Capabilities that existed in the 2.x version of the protocol
  # are still mandatory for clients. Clients cannot opt out of providing them.
  # So even if a client omits ClientCapabilities.textDocument.synchronization
  # it is still required that the client provides text document synchronization
  # (e.g. open, changed and close notifications).
  struct ClientCapabilities
    JSON.mapping({
      workspace: {type: WorkspaceClientCapabilities, default: WorkspaceClientCapabilities.new},
      text_document: {type: TextDocumentClientCapabilities, default: TextDocumentClientCapabilities.new, key: "textDocument"},
      experimental: {type: JSON::Any, default: JSON::Any.new({} of String => JSON::Any)},
    })
    def initialize(
      @workspace = WorkspaceClientCapabilities.new,
      @text_document = TextDocumentClientCapabilities.new,
      @experimental = JSON::Any.new({} of String => JSON::Any))
    end
  end
end
