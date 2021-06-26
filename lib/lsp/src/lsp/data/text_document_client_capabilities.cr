require "json"

module LSP::Data
  # Text document specific client capabilities.
  struct TextDocumentClientCapabilities
    include JSON::Serializable

    property synchronization : Synchronization = Synchronization.new

    # Capabilities specific to the `textDocument/completion`
    property completion : Completion = Completion.new

    # Capabilities specific to the `textDocument/hover`
    property hover : Hover = Hover.new

    # Capabilities specific to the `textDocument/signatureHelp`
    @[JSON::Field(key: "signatureHelp")]
    property signature_help : SignatureHelp = SignatureHelp.new

    # Capabilities specific to the `textDocument/references`
    property references : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `textDocument/documentHighlight`
    @[JSON::Field(key: "documentHighlight")]
    property document_highlight : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `textDocument/documentSymbol`
    @[JSON::Field(key: "documentSymbol")]
    property document_symbol : DocumentSymbol = DocumentSymbol.new

    # Capabilities specific to the `textDocument/formatting`
    property formatting : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `textDocument/rangeFormatting`
    @[JSON::Field(key: "rangeFormatting")]
    property range_formatting : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `textDocument/onTypeFormatting`
    @[JSON::Field(key: "onTypeFormatting")]
    property on_type_formatting : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `textDocument/definition`
    property definition : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `textDocument/typeDefinition`
    #
    # Since 3.6.0
    @[JSON::Field(key: "typeDefinition")]
    property type_definition : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `textDocument/implementation`.
    #
    # Since 3.6.0
    property implementation : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `textDocument/codeAction`
    @[JSON::Field(key: "codeAction")]
    property code_action : CodeAction = CodeAction.new

    # Capabilities specific to the `textDocument/codeLens`
    @[JSON::Field(key: "codeLens")]
    property code_lens : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `textDocument/documentLink`
    @[JSON::Field(key: "documentLink")]
    property document_link : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `textDocument/documentColor` and the
    # `textDocument/colorPresentation` request.
    #
    # Since 3.6.0
    @[JSON::Field(key: "colorProvider")]
    property color_provider : DynamicRegistration = DynamicRegistration.new

    # Capabilities specific to the `textDocument/rename`
    property rename : Rename = Rename.new

    # Capabilities specific to `textDocument/publishDiagnostics`.
    @[JSON::Field(key: "publishDiagnostics")]
    property publish_diagnostics : PublishDiagnostics = PublishDiagnostics.new

    # Capabilities specific to `textDocument/foldingRange` requests.
    #
    # Since 3.10.0
    @[JSON::Field(key: "foldingRange")]
    property folding_range : FoldingRange = FoldingRange.new

    def initialize
      @synchronization = Synchronization.new
      @completion = Completion.new
      @hover = Hover.new
      @signature_help = SignatureHelp.new
      @references = DynamicRegistration.new
      @document_highlight = DynamicRegistration.new
      @document_symbol = DocumentSymbol.new
      @formatting = DynamicRegistration.new
      @range_formatting = DynamicRegistration.new
      @on_type_formatting = DynamicRegistration.new
      @definition = DynamicRegistration.new
      @type_definition = DynamicRegistration.new
      @implementation = DynamicRegistration.new
      @code_action = CodeAction.new
      @code_lens = DynamicRegistration.new
      @document_link = DynamicRegistration.new
      @color_provider = DynamicRegistration.new
      @rename = Rename.new
      @publish_diagnostics = PublishDiagnostics.new
      @folding_range = FoldingRange.new
    end

    struct Synchronization
      include JSON::Serializable

      # Whether text document synchronization supports dynamic registration.
      @[JSON::Field(key: "dynamicRegistration")]
      property dynamic_registration : Bool = false

      # The client supports sending will save notifications.
      @[JSON::Field(key: "willSave")]
      property will_save : Bool = false

      # The client supports sending a will save request and
      # waits for a response providing text edits which will
      # be applied to the document before it is saved.
      @[JSON::Field(key: "willSaveWaitUntil")]
      property will_save_wait_until : Bool = false

      # The client supports did save notifications.
      @[JSON::Field(key: "didSave")]
      property did_save : Bool = false

      def initialize
        @dynamic_registration = false
        @will_save = false
        @will_save_wait_until = false
        @did_save = false
      end
    end

    struct Completion
      include JSON::Serializable

      # Whether completion supports dynamic registration.
      @[JSON::Field(key: "dynamicRegistration")]
      property dynamic_registration : Bool = false

      # The client supports the following `CompletionItem` specific
      # capabilities.
      @[JSON::Field(key: "completionItem")]
      property completion_item : CompletionItem = CompletionItem.new

      @[JSON::Field(key: "completionItemKind")]
      property completion_item_kind : CompletionItemKindSet = CompletionItemKindSet.new

      # The client supports to send additional context information for a
      # `textDocument/completion` request.
      @[JSON::Field(key: "contextSupport")]
      property context_support : Bool = false

      def initialize
        @dynamic_registration = false
        @completion_item = CompletionItem.new
        @completion_item_kind = CompletionItemKindSet.new
        @context_support = false
      end
    end

    struct CompletionItem
      include JSON::Serializable

      # Client supports snippets as insert text.
      #
      # A snippet can define tab stops and placeholders with `$1`, `$2`
      # and `${3:foo}`. `$0` defines the final tab stop, it defaults to
      # the end of the snippet. Placeholders with equal identifiers are linked,
      # that is typing in one will update others too.
      @[JSON::Field(key: "snippetSupport")]
      property snippet_support : Bool = false

      # Client supports commit characters on a completion item.
      @[JSON::Field(key: "commitCharactersSupport")]
      property commit_characters_support : Bool = false

      # Client supports the follow content formats for the documentation
      # property. The order describes the preferred format of the client.
      @[JSON::Field(key: "documentationFormat")]
      property documentation_format : Array(String) = [] of String

      # Client supports the deprecated property on a completion item.
      @[JSON::Field(key: "deprecatedSupport")]
      property deprecated_support : Bool = false

      # Client supports the preselect property on a completion item.
      @[JSON::Field(key: "preselectSupport")]
      property preselect_support : Bool = false

      def initialize
        @snippet_support = false
        @commit_characters_support = false
        @documentation_format = [] of String
        @deprecated_support = false
        @preselect_support = false
      end
    end

    struct Hover
      include JSON::Serializable

      # Whether hover supports dynamic registration.
      @[JSON::Field(key: "dynamicRegistration")]
      property dynamic_registration : Bool = false

      # Client supports the follow content formats for the content
      # property. The order describes the preferred format of the client.
      @[JSON::Field(key: "contentFormat")]
      property content_format : Array(String) = [] of String

      def initialize
        @dynamic_registration = false
        @content_format = [] of String
      end
    end

    struct SignatureHelp
      include JSON::Serializable

      # Whether signature help supports dynamic registration.
      @[JSON::Field(key: "dynamicRegistration")]
      property dynamic_registration : Bool = false

      # The client supports the following `SignatureInformation`
      # specific properties.
      @[JSON::Field(key: "signatureInformation")]
      property signature_information : SignatureInformation = SignatureInformation.new

      def initialize
        @dynamic_registration = false
        @signature_information = SignatureInformation.new
      end
    end

    struct SignatureInformation
      include JSON::Serializable

      # Client supports the follow content formats for the documentation
      # property. The order describes the preferred format of the client.
      @[JSON::Field(key: "documentationFormat")]
      property documentation_format : Array(String) = [] of String

      def initialize
        @documentation_format = [] of String
      end
    end

    struct DocumentSymbol
      include JSON::Serializable

      # Whether document symbol supports dynamic registration.
      @[JSON::Field(key: "dynamicRegistration")]
      property dynamic_registration : Bool = false

      # Specific capabilities for the `SymbolKind`.
      @[JSON::Field(key: "symbolKind")]
      property symbol_kind : SymbolKindSet = SymbolKindSet.new

      # The client support hierarchical document symbols.
      @[JSON::Field(key: "hierarchicalDocumentSymbolSupport")]
      property hierarchical_document_symbol_support : Bool = false

      def initialize
        @dynamic_registration = false
        @symbol_kind = SymbolKindSet.new
        @hierarchical_document_symbol_support = false
      end
    end

    struct CodeAction
      include JSON::Serializable

      # Whether code action supports dynamic registration.
      @[JSON::Field(key: "dynamicRegistration")]
      property dynamic_registration : Bool = false

      # The client support code action literals as a valid
      # response of the `textDocument/codeAction` request.
      #
      # Since 3.8.0
      @[JSON::Field(key: "codeActionLiteralSupport")]
      property code_action_literal_support : CodeActionLiteralSupport = CodeActionLiteralSupport.new

      def initialize
        @dynamic_registration = false
        @code_action_literal_support = CodeActionLiteralSupport.new
      end
    end

    struct CodeActionLiteralSupport
      include JSON::Serializable

      # The code action kind is support with the following value
      # set.
      @[JSON::Field(key: "codeActionKind")]
      property code_action_kind : CodeActionKindSet = CodeActionKindSet.new

      def initialize
        @code_action_kind = CodeActionKindSet.new
      end
    end

    struct Rename
      include JSON::Serializable

      # Whether rename supports dynamic registration.
      @[JSON::Field(key: "dynamicRegistration")]
      property dynamic_registration : Bool = false

      # Client supports testing for validity of rename operations
      # before execution.
      @[JSON::Field(key: "prepareSupport")]
      property prepare_support : Bool = false

      def initialize
        @dynamic_registration = false
        @prepare_support = false
      end
    end

    struct PublishDiagnostics
      include JSON::Serializable

      # Whether the clients accepts diagnostics with related information.
      @[JSON::Field(key: "relatedInformation")]
      property related_information : Bool = false

      def initialize
        @related_information = false
      end
    end

    struct FoldingRange
      include JSON::Serializable

      # Whether implementation supports dynamic registration for folding range providers. If this is set to `true`
      # the client supports the new `(FoldingRangeProviderOptions & TextDocumentRegistrationOptions & StaticRegistrationOptions)`
      # return value for the corresponding server capability as well.
      @[JSON::Field(key: "dynamicRegistration")]
      property dynamic_registration : Bool = false
      # The maximum number of folding ranges that the client prefers to receive per document. The value serves as a
      # hint, servers are free to follow the limit.
      @[JSON::Field(key: "rangeLimit")]
      property range_limit : Int64 = 0_i64
      # If set, the client signals that it only supports folding complete lines. If set, client will
      # ignore specified `startCharacter` and `endCharacter` properties in a FoldingRange.
      @[JSON::Field(key: "lineFoldingOnly")]
      property line_folding_only : Bool = false

      def initialize
        @dynamic_registration = false
        @range_limit = 0
        @line_folding_only = false
      end
    end
  end
end
