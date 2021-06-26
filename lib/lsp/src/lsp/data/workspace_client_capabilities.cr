require "json"

module LSP::Data
  # Workspace specific client capabilities.
  struct WorkspaceClientCapabilities
    include JSON::Serializable

    # The client supports applying batch edits to the workspace by supporting
    # the request 'workspace/applyEdit'
    @[JSON::Field(key: "applyEdit")]
    property apply_edit : Bool = false

    # Capabilities specific to `WorkspaceEdit`s
    @[JSON::Field(key: "workspaceEdit")]
    property workspace_edit : WorkspaceEdit = WorkspaceEdit.new

    # Capabilities specific to the `workspace/didChangeConfiguration` notification.
    @[JSON::Field(key: "didChangeConfiguration")]
    property did_change_configuration : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `workspace/didChangeWatchedFiles` notification.
    @[JSON::Field(key: "didChangeWatchedFiles")]
    property did_change_watched_files : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `workspace/symbol` request.
    property symbol : WorkspaceSymbol = WorkspaceSymbol.new

    # Capabilities specific to the `workspace/executeCommand` request.
    @[JSON::Field(key: "executeCommand")]
    property execute_command : DynamicRegistration = DynamicRegistration.new

    # The client has support for workspace folders.
    #
    # Since 3.6.0
    @[JSON::Field(key: "workspaceFolders")]
    property workspace_folders : Bool = false

    # The client supports `workspace/configuration` requests.
    #
    # Since 3.6.0
    property configuration : Bool = false

    def initialize
      @apply_edit = false
      @workspace_edit = WorkspaceEdit.new
      @did_change_configuration = DynamicRegistration.new
      @did_change_watched_files = DynamicRegistration.new
      @symbol = WorkspaceSymbol.new
      @execute_command = DynamicRegistration.new
      @workspace_folders = false
      @configuration = false
    end

    struct WorkspaceEdit
      include JSON::Serializable

      # The client supports versioned document changes in `WorkspaceEdit`s
      @[JSON::Field(key: "documentChanges")]
      property document_changes : Bool = false

      # The resource operations the client supports. Clients should at least
      # support 'create', 'rename' and 'delete' files and folders.
      @[JSON::Field(key: "resourceOperations")]
      property resource_operations : Array(String) = [] of String

      # The failure handling strategy of a client if applying the workspace edit
      # failes.
      @[JSON::Field(key: "failureHandling")]
      property failure_handling : String = "abort"

      def initialize
        @document_changes = false
        @resource_operations = [] of String
        @failure_handling = "abort"
      end
    end

    struct WorkspaceSymbol
      include JSON::Serializable

      # Symbol request supports dynamic registration.
      @[JSON::Field(key: "dynamicRegistration")]
      property dynamic_registration : Bool = false

      # Specific capabilities for the `SymbolKind` in the `workspace/symbol` request.
      @[JSON::Field(key: "symbolKind")]
      property symbol_kind : SymbolKindSet = SymbolKindSet.new

      def initialize
        @dynamic_registration = false
        @symbol_kind = SymbolKindSet.new
      end
    end
  end
end
