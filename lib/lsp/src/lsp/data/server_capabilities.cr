require "json"

module LSP::Data
  struct ServerCapabilities
    JSON.mapping({
      # Defines how text documents are synced. Is either a detailed structure defining each notification or
      # for backwards compatibility the TextDocumentSyncKind number. If omitted it defaults to `TextDocumentSyncKind.None`.
      text_document_sync: {type: TextDocumentSyncOptions, default: TextDocumentSyncOptions.new, key: "textDocumentSync"},
      
      # The server provides hover support.
      hover_provider: {type: Bool, default: false, key: "hoverProvider"},
      
      # The server provides completion support.
      completion_provider: {type: CompletionOptions?, key: "completionProvider"},
      
      # The server provides signature help support.
      signature_help_provider: {type: SignatureHelpOptions?, key: "signatureHelpProvider"},
      
      # The server provides goto definition support.
      definition_provider: {type: Bool, default: false, key: "definitionProvider"},
      
      # The server provides Goto Type Definition support.
      #
      # Since 3.6.0
      type_definition_provider: {type: Bool | StaticRegistrationOptions, default: false, key: "typeDefinitionProvider"},
      
      # The server provides Goto Implementation support.
      #
      # Since 3.6.0
      implementation_provider: {type: Bool | StaticRegistrationOptions, default: false, key: "implementationProvider"},
      
      # The server provides find references support.
      references_provider: {type: Bool, default: false, key: "referencesProvider"},
      
      # The server provides document highlight support.
      document_highlight_provider: {type: Bool, default: false, key: "documentHighlightProvider"},
      
      # The server provides document symbol support.
      document_symbol_provider: {type: Bool, default: false, key: "documentSymbolProvider"},
      
      # The server provides workspace symbol support.
      workspace_symbol_provider: {type: Bool, default: false, key: "workspaceSymbolProvider"},
      
      # The server provides code actions. The `CodeActionOptions` return type is only
      # valid if the client signals code action literal support via the property
      # `textDocument.codeAction.codeActionLiteralSupport`.
      code_action_provider: {type: Bool | CodeActionOptions, default: false, key: "codeActionProvider"},
      
      # The server provides code lens.
      code_lens_provider: {type: CodeLensOptions?, key: "codeLensProvider"},
      
      # The server provides document formatting.
      document_formatting_provider: {type: Bool, default: false, key: "documentFormattingProvider"},
      
      # The server provides document range formatting.
      document_range_formatting_provider: {type: Bool, default: false, key: "documentRangeFormattingProvider"},
      
      # The server provides document formatting on typing.
      document_on_type_formatting_provider: {type: DocumentOnTypeFormattingOptions?, key: "documentOnTypeFormattingProvider"},
      
      # The server provides rename support. RenameOptions may only be
      # specified if the client states that it supports
      # `prepareSupport` in its initial `initialize` request.
      rename_provider: {type: Bool | RenameOptions, default: false, key: "renameProvider"},
      
      # The server provides document link support.
      document_link_provider: {type: DocumentLinkOptions?, key: "documentLinkProvider"},
      
      # The server provides color provider support.
      #
      # Since 3.6.0
      color_provider: {type: Bool | StaticRegistrationOptions, default: false, key: "colorProvider"},
      
      # The server provides folding provider support.
      #
      # Since 3.10.0
      folding_range_provider: {type: Bool | StaticRegistrationOptions, default: false, key: "foldingRangeProvider"},
      
      # The server provides execute command support.
      execute_command_provider: {type: ExecuteCommandOptions?, key: "executeCommandProvider"},
      
      # Workspace specific server capabilities
      workspace: {type: WorkspaceOptions, default: WorkspaceOptions.new},
      
      # Experimental server capabilities.
      experimental: {type: JSON::Any, default: JSON::Any.new({} of String => JSON::Any)},
    })
    
    def initialize
      @text_document_sync = TextDocumentSyncOptions.new
      @hover_provider = false
      @completion_provider = nil
      @signature_help_provider = nil
      @definition_provider = false
      @type_definition_provider = false
      @implementation_provider = false
      @references_provider = false
      @document_highlight_provider = false
      @document_symbol_provider = false
      @workspace_symbol_provider = false
      @code_action_provider = false
      @code_lens_provider = nil
      @document_formatting_provider = false
      @document_range_formatting_provider = false
      @document_on_type_formatting_provider = nil
      @rename_provider = false
      @document_link_provider = nil
      @color_provider = false
      @folding_range_provider = false
      @execute_command_provider = nil
      @workspace = WorkspaceOptions.new
      @experimental = JSON::Any.new({} of String => JSON::Any)
    end
    
    struct CompletionOptions
      JSON.mapping({
        # The server provides support to resolve additional
        # information for a completion item.
        resolve_provider: {type: Bool, default: false, key: "resolveProvider"},
        
        # The characters that trigger completion automatically.
        trigger_characters: {type: Array(String), default: [] of String, key: "triggerCharacters"},
      })
      def initialize(
        @resolve_provider = false,
        @trigger_characters = [] of String)
      end
    end
    
    struct SignatureHelpOptions
      JSON.mapping({
        # The characters that trigger signature help
        # automatically.
        trigger_characters: {type: Array(String), default: [] of String, key: "triggerCharacters"},
      })
      def initialize(@trigger_characters = [] of String)
      end
    end
    
    struct CodeActionOptions
      JSON.mapping({
        # CodeActionKinds that this server may return.
        #
        # The list of kinds may be generic, such as `CodeActionKind.Refactor`, or the server
        # may list out every specific kind they provide.
        code_action_kinds: {type: Array(String), default: [] of String, key: "codeActionKinds"},
      })
      def initialize(@code_action_kinds = [] of String)
      end
    end
    
    struct CodeLensOptions
      JSON.mapping({
        # Code lens has a resolve provider as well.
        resolve_provider: {type: Bool, default: false, key: "resolveProvider"},
      })
      def initialize(@resolve_provider = false)
      end
    end
    
    struct DocumentOnTypeFormattingOptions
      JSON.mapping({
        # A character on which formatting should be triggered, like `}`.
        first_trigger_character: {type: String, key: "firstTriggerCharacter"},
        
        # More trigger characters.
        more_trigger_character: {type: Array(String), default: [] of String, key: "moreTriggerCharacter"},
      })
      def initialize(@first_trigger_character, *more)
        @more_trigger_character = more.to_a
      end
    end
    
    struct RenameOptions
      JSON.mapping({
        # Renames should be checked and tested before being executed.
        prepare_provider: {type: Bool, default: false, key: "prepareProvider"},
      })
      def initialize(@prepare_provider = false)
      end
    end
    
    struct DocumentLinkOptions
      JSON.mapping({
        # Document links have a resolve provider as well.
        resolve_provider: {type: Bool, default: false, key: "resolveProvider"},
      })
      def initialize(@resolve_provider = false)
      end
    end
    
    struct ExecuteCommandOptions
      JSON.mapping({
        # The commands to be executed on the server
        commands: {type: Array(String), default: [] of String},
      })
      def initialize(@commands = [] of String)
      end
    end
    
    struct SaveOptions
      JSON.mapping({
        # The client is supposed to include the content on save.
        include_text: {type: Bool, default: false, key: "includeText"},
      })
      def initialize(@include_text = false)
      end
    end
    
    struct TextDocumentSyncOptions
      JSON.mapping({
        # Open and close notifications are sent to the server.
        open_close: {type: Bool, default: false, key: "openClose"},
        
        # Change notifications are sent to the server. See TextDocumentSyncKind.None, TextDocumentSyncKind.Full
        # and TextDocumentSyncKind.Incremental. If omitted it defaults to TextDocumentSyncKind.None.
        change: {type: TextDocumentSyncKind, default: TextDocumentSyncKind::None},
        
        # Will save notifications are sent to the server.
        will_save: {type: Bool, default: false, key: "willSave"},
        
        # Will save wait until requests are sent to the server.
        will_save_wait_until: {type: Bool, default: false, key: "willSaveWaitUntil"},
        
        # Save notifications are sent to the server.
        save: {type: SaveOptions?},
      })
      def initialize
        @open_close = false
        @change = TextDocumentSyncKind::None
        @will_save = false
        @will_save_wait_until = false
        @save = nil
      end
    end
    
    struct StaticRegistrationOptions
      JSON.mapping({
        # A document selector to identify the scope of the registration. If set
        # to null the document selector provided on the client side will be used.
        document_selector: {
          type: Array(DocumentFilter)?,
          emit_null: true,
          key: "documentSelector"
        },
        
        # The id used to register the request. The id can be used to deregister
        # the request again. See also Registration#id.
        id: String?,
      })
      def initialize(@document_selector = [] of DocumentFilter, @id = nil)
      end
    end
    
    struct WorkspaceOptions
      JSON.mapping({
        # The server support for workspace folders.
        #
        # Since 3.6.0
        workspace_folders: {type: WorkspaceFoldersOptions, default: WorkspaceFoldersOptions.new, key: "workspaceFolders"},
      })
      def initialize
        @workspace_folders = WorkspaceFoldersOptions.new
      end
    end
    
    struct WorkspaceFoldersOptions
      JSON.mapping({
        # The server has support for workspace folders
        supported: {type: Bool, default: false},
        
        # Whether the server wants to receive workspace folder
        # change notifications.
        #
        # If a strings is provided the string is treated as a ID
        # under which the notification is registered on the client
        # side. The ID can be used to unregister for these events
        # using the `client/unregisterCapability` request.
        change_notifications: {type: (Bool | String), default: false, key: "changeNotifications"},
      })
      def initialize
        @supported = false
        @change_notifications = false
      end
    end
  end
end
