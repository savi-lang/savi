require "json"

module LSP::Data
  struct ServerCapabilities
    include JSON::Serializable

    # Defines how text documents are synced. Is either a detailed structure defining each notification or
    # for backwards compatibility the TextDocumentSyncKind number. If omitted it defaults to `TextDocumentSyncKind.None`.
    @[JSON::Field(key: "textDocumentSync")]
    property text_document_sync : TextDocumentSyncOptions = TextDocumentSyncOptions.new

    # The server provides hover support.
    @[JSON::Field(key: "hoverProvider")]
    property hover_provider : Bool = false

    # The server provides completion support.
    @[JSON::Field(key: "completionProvider")]
    property completion_provider : CompletionOptions?

    # The server provides signature help support.
    @[JSON::Field(key: "signatureHelpProvider")]
    property signature_help_provider : SignatureHelpOptions?

    # The server provides goto definition support.
    @[JSON::Field(key: "definitionProvider")]
    property definition_provider : Bool = false

    # The server provides Goto Type Definition support.
    #
    # Since 3.6.0
    @[JSON::Field(key: "typeDefinitionProvider")]
    property type_definition_provider : Bool | StaticRegistrationOptions = false

    # The server provides Goto Implementation support.
    #
    # Since 3.6.0
    @[JSON::Field(key: "implementationProvider")]
    property implementation_provider : Bool | StaticRegistrationOptions = false

    # The server provides find references support.
    @[JSON::Field(key: "referencesProvider")]
    property references_provider : Bool = false

    # The server provides document highlight support.
    @[JSON::Field(key: "documentHighlightProvider")]
    property document_highlight_provider : Bool = false

    # The server provides document symbol support.
    @[JSON::Field(key: "documentSymbolProvider")]
    property document_symbol_provider : Bool = false

    # The server provides workspace symbol support.
    @[JSON::Field(key: "workspaceSymbolProvider")]
    property workspace_symbol_provider : Bool = false

    # The server provides code actions. The `CodeActionOptions` return type is only
    # valid if the client signals code action literal support via the property
    # `textDocument.codeAction.codeActionLiteralSupport`.
    @[JSON::Field(key: "codeActionProvider")]
    property code_action_provider : Bool | CodeActionOptions = false

    # The server provides code lens.
    @[JSON::Field(key: "codeLensProvider")]
    property code_lens_provider : CodeLensOptions?

    # The server provides document formatting.
    @[JSON::Field(key: "documentFormattingProvider")]
    property document_formatting_provider : Bool = false

    # The server provides document range formatting.
    @[JSON::Field(key: "documentRangeFormattingProvider")]
    property document_range_formatting_provider : Bool = false

    # The server provides document formatting on typing.
    @[JSON::Field(key: "documentOnTypeFormattingProvider")]
    property document_on_type_formatting_provider : DocumentOnTypeFormattingOptions?

    # The server provides rename support. RenameOptions may only be
    # specified if the client states that it supports
    # `prepareSupport` in its initial `initialize` request.
    @[JSON::Field(key: "renameProvider")]
    property rename_provider : Bool | RenameOptions = false

    # The server provides document link support.
    @[JSON::Field(key: "documentLinkProvider")]
    property document_link_provider : DocumentLinkOptions?

    # The server provides color provider support.
    #
    # Since 3.6.0
    @[JSON::Field(key: "colorProvider")]
    property color_provider : Bool | StaticRegistrationOptions = false

    # The server provides folding provider support.
    #
    # Since 3.10.0
    @[JSON::Field(key: "foldingRangeProvider")]
    property folding_range_provider : Bool | StaticRegistrationOptions = false

    # The server provides execute command support.
    @[JSON::Field(key: "executeCommandProvider")]
    property execute_command_provider : ExecuteCommandOptions?

    # Workspace specific server capabilities
    property workspace : WorkspaceOptions = WorkspaceOptions.new

    # Experimental server capabilities.
    property experimental : JSON::Any = JSON::Any.new({} of String => JSON::Any)

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
      include JSON::Serializable

      # The server provides support to resolve additional
      # information for a completion item.
      @[JSON::Field(key: "resolveProvider")]
      property resolve_provider : Bool = false

      # The characters that trigger completion automatically.
      @[JSON::Field(key: "triggerCharacters")]
      property trigger_characters : Array(String) = [] of String

      def initialize(
        @resolve_provider = false,
        @trigger_characters = [] of String
      )
      end
    end

    struct SignatureHelpOptions
      include JSON::Serializable

      # The characters that trigger signature help
      # automatically.
      @[JSON::Field(key: "triggerCharacters")]
      property trigger_characters : Array(String) = [] of String

      def initialize(@trigger_characters = [] of String)
      end
    end

    struct CodeActionOptions
      include JSON::Serializable

      # CodeActionKinds that this server may return.
      #
      # The list of kinds may be generic, such as `CodeActionKind.Refactor`, or the server
      # may list out every specific kind they provide.
      @[JSON::Field(key: "codeActionKinds")]
      property code_action_kinds : Array(String) = [] of String

      def initialize(@code_action_kinds = [] of String)
      end
    end

    struct CodeLensOptions
      include JSON::Serializable

      # Code lens has a resolve provider as well.
      @[JSON::Field(key: "resolveProvider")]
      property resolve_provider : Bool = false

      def initialize(@resolve_provider = false)
      end
    end

    struct DocumentOnTypeFormattingOptions
      include JSON::Serializable

      # A character on which formatting should be triggered, like `}`.
      @[JSON::Field(key: "firstTriggerCharacter")]
      property first_trigger_character : String

      # More trigger characters.
      @[JSON::Field(key: "moreTriggerCharacter")]
      property more_trigger_character : Array(String) = [] of String

      def initialize(@first_trigger_character, *more)
        @more_trigger_character = more.to_a
      end
    end

    struct RenameOptions
      include JSON::Serializable

      # Renames should be checked and tested before being executed.
      @[JSON::Field(key: "prepareProvider")]
      property prepare_provider : Bool = false

      def initialize(@prepare_provider = false)
      end
    end

    struct DocumentLinkOptions
      include JSON::Serializable

      # Document links have a resolve provider as well.
      @[JSON::Field(key: "resolveProvider")]
      property resolve_provider : Bool = false

      def initialize(@resolve_provider = false)
      end
    end

    struct ExecuteCommandOptions
      include JSON::Serializable

      # The commands to be executed on the server
      property commands : Array(String) = [] of String

      def initialize(@commands = [] of String)
      end
    end

    struct SaveOptions
      include JSON::Serializable

      # The client is supposed to include the content on save.
      @[JSON::Field(key: "includeText")]
      property include_text : Bool = false

      def initialize(@include_text = false)
      end
    end

    struct TextDocumentSyncOptions
      include JSON::Serializable

      # Open and close notifications are sent to the server.
      @[JSON::Field(key: "openClose")]
      property open_close : Bool = false

      # Change notifications are sent to the server. See TextDocumentSyncKind.None, TextDocumentSyncKind.Full
      # and TextDocumentSyncKind.Incremental. If omitted it defaults to TextDocumentSyncKind.None.
      @[JSON::Field(converter: Enum::ValueConverter(LSP::Data::TextDocumentSyncKind))]
      property change : TextDocumentSyncKind = TextDocumentSyncKind::None

      # Will save notifications are sent to the server.
      @[JSON::Field(key: "willSave")]
      property will_save : Bool = false

      # Will save wait until requests are sent to the server.
      @[JSON::Field(key: "willSaveWaitUntil")]
      property will_save_wait_until : Bool = false

      # Save notifications are sent to the server.
      property save : SaveOptions?

      def initialize
        @open_close = false
        @change = TextDocumentSyncKind::None
        @will_save = false
        @will_save_wait_until = false
        @save = nil
      end
    end

    struct StaticRegistrationOptions
      include JSON::Serializable

      # A document selector to identify the scope of the registration. If set
      # to null the document selector provided on the client side will be used.
      @[JSON::Field(key: "documentSelector", emit_null: true)]
      property document_selector : Array(DocumentFilter)?

      # The id used to register the request. The id can be used to deregister
      # the request again. See also Registration#id.
      property id : String?

      def initialize(@document_selector = [] of DocumentFilter, @id = nil)
      end
    end

    struct WorkspaceOptions
      include JSON::Serializable

      # The server support for workspace folders.
      #
      # Since 3.6.0
      @[JSON::Field(key: "workspaceFolders")]
      property workspace_folders : WorkspaceFoldersOptions = WorkspaceFoldersOptions.new

      def initialize
        @workspace_folders = WorkspaceFoldersOptions.new
      end
    end

    struct WorkspaceFoldersOptions
      include JSON::Serializable

      # The server has support for workspace folders
      property supported : Bool = false

      # Whether the server wants to receive workspace folder
      # change notifications.
      #
      # If a strings is provided the string is treated as a ID
      # under which the notification is registered on the client
      # side. The ID can be used to unregister for these events
      # using the `client/unregisterCapability` request.
      @[JSON::Field(key: "changeNotifications")]
      property change_notifications : (Bool | String) = false

      def initialize
        @supported = false
        @change_notifications = false
      end
    end
  end
end
