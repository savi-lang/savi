require "json"

module LSP::Data
  # Text document specific client capabilities.
  struct TextDocumentClientCapabilities
    JSON.mapping({
      synchronization: {type: Synchronization, default: Synchronization.new},
      
      # Capabilities specific to the `textDocument/completion`
      completion: {type: Completion, default: Completion.new},
      
      # Capabilities specific to the `textDocument/hover`
      hover: {type: Hover, default: Hover.new},
      
      # Capabilities specific to the `textDocument/signatureHelp`
      signature_help: {type: SignatureHelp, default: SignatureHelp.new, key: "signatureHelp" },
      
      # Capabilities specific to the `textDocument/references`
      references: {type: DynamicRegistration, default: DynamicRegistration.new},
      
      # Capabilities specific to the `textDocument/documentHighlight`
      document_highlight: {type: DynamicRegistration, default: DynamicRegistration.new, key: "documentHighlight"},
      
      # Capabilities specific to the `textDocument/documentSymbol`
      document_symbol: {type: DocumentSymbol, default: DocumentSymbol.new, key: "documentSymbol" },
      
      # Capabilities specific to the `textDocument/formatting`
      formatting: {type: DynamicRegistration, default: DynamicRegistration.new},
      
      # Capabilities specific to the `textDocument/rangeFormatting`
      range_formatting: {type: DynamicRegistration, default: DynamicRegistration.new, key: "rangeFormatting"},
      
      # Capabilities specific to the `textDocument/onTypeFormatting`
      on_type_formatting: {type: DynamicRegistration, default: DynamicRegistration.new, key: "onTypeFormatting"},
      
      # Capabilities specific to the `textDocument/definition`
      definition: {type: DynamicRegistration, default: DynamicRegistration.new},
      
      # Capabilities specific to the `textDocument/typeDefinition`
      #
      # Since 3.6.0
      type_definition: {type: DynamicRegistration, default: DynamicRegistration.new, key: "typeDefinition"},
      
      # Capabilities specific to the `textDocument/implementation`.
      #
      # Since 3.6.0
      implementation: {type: DynamicRegistration, default: DynamicRegistration.new},
      
      # Capabilities specific to the `textDocument/codeAction`
      code_action: {type: CodeAction, default: CodeAction.new, key: "codeAction" },
      
      # Capabilities specific to the `textDocument/codeLens`
      code_lens: {type: DynamicRegistration, default: DynamicRegistration.new, key: "codeLens"},
      
      # Capabilities specific to the `textDocument/documentLink`
      document_link: {type: DynamicRegistration, default: DynamicRegistration.new, key: "documentLink"},
      
      # Capabilities specific to the `textDocument/documentColor` and the
      # `textDocument/colorPresentation` request.
      #
      # Since 3.6.0
      color_provider: {type: DynamicRegistration, default: DynamicRegistration.new, key: "colorProvider"},
      
      # Capabilities specific to the `textDocument/rename`
      rename: {type: Rename, default: Rename.new},
      
      # Capabilities specific to `textDocument/publishDiagnostics`.
      publish_diagnostics: {type: PublishDiagnostics, default: PublishDiagnostics.new, key: "publishDiagnostics" },
      
      # Capabilities specific to `textDocument/foldingRange` requests.
      #
      # Since 3.10.0
      folding_range: {type: FoldingRange, default: FoldingRange.new, key: "foldingRange"},
    })
    
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
      JSON.mapping({
        # Whether text document synchronization supports dynamic registration.
        dynamic_registration: {type: Bool, default: false, key: "dynamicRegistration"},
        
        # The client supports sending will save notifications.
        will_save: {type: Bool, default: false, key: "willSave"},
        
        # The client supports sending a will save request and
        # waits for a response providing text edits which will
        # be applied to the document before it is saved.
        will_save_wait_until: {type: Bool, default: false, key: "willSaveWaitUntil"},
        
        # The client supports did save notifications.
        did_save: {type: Bool, default: false, key: "didSave"},
      })
      def initialize
        @dynamic_registration = false
        @will_save = false
        @will_save_wait_until = false
        @did_save = false
      end
    end
    
    struct Completion
      JSON.mapping({
        # Whether completion supports dynamic registration.
        dynamic_registration: {type: Bool, default: false, key: "dynamicRegistration"},
        
        # The client supports the following `CompletionItem` specific
        # capabilities.
        completion_item: {type: CompletionItem, default: CompletionItem.new, key: "completionItem" },
        
        completion_item_kind: {type: CompletionItemKindSet, default: CompletionItemKindSet.new, key: "completionItemKind"},
        
        # The client supports to send additional context information for a
        # `textDocument/completion` request.
        context_support: {type: Bool, default: false, key: "contextSupport"},
      })
      def initialize
        @dynamic_registration = false
        @completion_item = CompletionItem.new
        @completion_item_kind = CompletionItemKindSet.new
        @context_support = false
      end
    end
    
    struct CompletionItem
      JSON.mapping({
        # Client supports snippets as insert text.
        #
        # A snippet can define tab stops and placeholders with `$1`, `$2`
        # and `${3:foo}`. `$0` defines the final tab stop, it defaults to
        # the end of the snippet. Placeholders with equal identifiers are linked,
        # that is typing in one will update others too.
        snippet_support: {type: Bool, default: false, key: "snippetSupport"},
        
        # Client supports commit characters on a completion item.
        commit_characters_support: {type: Bool, default: false, key: "commitCharactersSupport"},
        
        # Client supports the follow content formats for the documentation
        # property. The order describes the preferred format of the client.
        documentation_format: {type: Array(String), default: [] of String, key: "documentationFormat"},
        
        # Client supports the deprecated property on a completion item.
        deprecated_support: {type: Bool, default: false, key: "deprecatedSupport"},
        
        # Client supports the preselect property on a completion item.
        preselect_support: {type: Bool, default: false, key: "preselectSupport"},
      })
      def initialize
        @snippet_support = false
        @commit_characters_support = false
        @documentation_format = [] of String
        @deprecated_support = false
        @preselect_support = false
      end
    end
    
    struct Hover
      JSON.mapping({
        # Whether hover supports dynamic registration.
        dynamic_registration: {type: Bool, default: false, key: "dynamicRegistration"},
        
        # Client supports the follow content formats for the content
        # property. The order describes the preferred format of the client.
        content_format: {type: Array(String), default: [] of String, key: "contentFormat"},
      })
      def initialize
        @dynamic_registration = false
        @content_format = [] of String
      end
    end
    
    struct SignatureHelp
      JSON.mapping({
        # Whether signature help supports dynamic registration.
        dynamic_registration: {type: Bool, default: false, key: "dynamicRegistration"},
        
        # The client supports the following `SignatureInformation`
        # specific properties.
        signature_information: {type: SignatureInformation, default: SignatureInformation.new, key: "signatureInformation" },
      })
      def initialize
        @dynamic_registration = false
        @signature_information = SignatureInformation.new
      end
    end
    
    struct SignatureInformation
      JSON.mapping({
        # Client supports the follow content formats for the documentation
        # property. The order describes the preferred format of the client.
        documentation_format: {type: Array(String), default: [] of String, key: "documentationFormat"},
      })
      def initialize
        @documentation_format = [] of String
      end
    end
    
    struct DocumentSymbol
      JSON.mapping({
        # Whether document symbol supports dynamic registration.
        dynamic_registration: {type: Bool, default: false, key: "dynamicRegistration"},
        
        # Specific capabilities for the `SymbolKind`.
        symbol_kind: {type: SymbolKindSet, default: SymbolKindSet.new, key: "symbolKind"},
        
        # The client support hierarchical document symbols.
        hierarchical_document_symbol_support: {type: Bool, default: false, key: "hierarchicalDocumentSymbolSupport"},
      })
      def initialize
        @dynamic_registration = false
        @symbol_kind = SymbolKindSet.new
        @hierarchical_document_symbol_support = false
      end
    end
    
    struct CodeAction
      JSON.mapping({
        # Whether code action supports dynamic registration.
        dynamic_registration: {type: Bool, default: false, key: "dynamicRegistration"},
        
        # The client support code action literals as a valid
        # response of the `textDocument/codeAction` request.
        #
        # Since 3.8.0
        code_action_literal_support: {type: CodeActionLiteralSupport, default: CodeActionLiteralSupport.new, key: "codeActionLiteralSupport" },
      })
      def initialize
        @dynamic_registration = false
        @code_action_literal_support = CodeActionLiteralSupport.new
      end
    end
    
    struct CodeActionLiteralSupport
      JSON.mapping({
        # The code action kind is support with the following value
        # set.
        code_action_kind: {type: CodeActionKindSet, default: CodeActionKindSet.new, key: "codeActionKind"},
      })
      def initialize
        @code_action_kind = CodeActionKindSet.new
      end
    end
    
    struct Rename
      JSON.mapping({
        # Whether rename supports dynamic registration.
        dynamic_registration: {type: Bool, default: false, key: "dynamicRegistration"},
        
        # Client supports testing for validity of rename operations
        # before execution.
        prepare_support: {type: Bool, default: false, key: "prepareSupport"},
      })
      def initialize
        @dynamic_registration = false
        @prepare_support = false
      end
    end
    
    struct PublishDiagnostics
      JSON.mapping({
        # Whether the clients accepts diagnostics with related information.
        related_information: {type: Bool, default: false, key: "relatedInformation"},
      })
      def initialize
        @related_information = false
      end
    end
    
    struct FoldingRange
      JSON.mapping({
        # Whether implementation supports dynamic registration for folding range providers. If this is set to `true`
        # the client supports the new `(FoldingRangeProviderOptions & TextDocumentRegistrationOptions & StaticRegistrationOptions)`
        # return value for the corresponding server capability as well.
        dynamic_registration: {type: Bool, default: false, key: "dynamicRegistration"},
        # The maximum number of folding ranges that the client prefers to receive per document. The value serves as a
        # hint, servers are free to follow the limit.
        range_limit: {type: Int64, default: 0_i64, key: "rangeLimit"},
        # If set, the client signals that it only supports folding complete lines. If set, client will
        # ignore specified `startCharacter` and `endCharacter` properties in a FoldingRange.
        line_folding_only: {type: Bool, default: false, key: "lineFoldingOnly"},
      })
      def initialize
        @dynamic_registration = false
        @range_limit = 0
        @line_folding_only = false
      end
    end
  end
end
