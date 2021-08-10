require "json"

module LSP::Data
  # Workspace specific client capabilities.
  struct WorkspaceClientCapabilities
    JSON.mapping({
      # The client supports applying batch edits to the workspace by supporting
      # the request 'workspace/applyEdit'
      apply_edit: {type: Bool, default: false, key: "applyEdit"},

      # Capabilities specific to `WorkspaceEdit`s
      workspace_edit: {
        type: WorkspaceEdit,
        default: WorkspaceEdit.new,
        key: "workspaceEdit",
      },

      # Capabilities specific to the `workspace/didChangeConfiguration` notification.
      did_change_configuration: {
        type: DynamicRegistration,
        default: DynamicRegistration.new,
        key: "didChangeConfiguration",
      },

      # Capabilities specific to the `workspace/didChangeWatchedFiles` notification.
      did_change_watched_files: {
        type: DynamicRegistration,
        default: DynamicRegistration.new,
        key: "didChangeWatchedFiles",
      },

      # Capabilities specific to the `workspace/symbol` request.
      symbol: {type: WorkspaceSymbol, default: WorkspaceSymbol.new},

      # Capabilities specific to the `workspace/executeCommand` request.
      execute_command: {
        type: DynamicRegistration,
        default: DynamicRegistration.new,
        key: "executeCommand",
      },

      # The client has support for workspace folders.
      #
      # Since 3.6.0
      workspace_folders: {type: Bool, default: false, key: "workspaceFolders"},

      # The client supports `workspace/configuration` requests.
      #
      # Since 3.6.0
      configuration: {type: Bool, default: false},
    })

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
      JSON.mapping({
        # The client supports versioned document changes in `WorkspaceEdit`s
        document_changes: {type: Bool, default: false, key: "documentChanges"},

        # The resource operations the client supports. Clients should at least
        # support 'create', 'rename' and 'delete' files and folders.
        resource_operations: {
          type: Array(String),
          default: [] of String,
          key: "resourceOperations",
        },

        # The failure handling strategy of a client if applying the workspace edit
        # failes.
        failure_handling: {
          type: String,
          default: "abort",
          key: "failureHandling",
        },
      })
      def initialize
        @document_changes = false
        @resource_operations = [] of String
        @failure_handling = "abort"
      end
    end

    struct WorkspaceSymbol
      JSON.mapping({
        # Symbol request supports dynamic registration.
        dynamic_registration: {
          type: Bool,
          default: false,
          key: "dynamicRegistration",
        },

        # Specific capabilities for the `SymbolKind` in the `workspace/symbol` request.
        symbol_kind: {
          type: SymbolKindSet,
          default: SymbolKindSet.new,
          key: "symbolKind",
        },
      })
      def initialize
        @dynamic_registration = false
        @symbol_kind = SymbolKindSet.new
      end
    end
  end
end
