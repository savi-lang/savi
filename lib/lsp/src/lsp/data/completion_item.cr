require "json"

module LSP::Data
  struct CompletionItem
    include JSON::Serializable

    # The label of this completion item. By default
    # also the text that is inserted when selecting
    # this completion.
    property label : String

    # The kind of this completion item. Based of the kind
    # an icon is chosen by the editor.
    @[JSON::Field(converter: Enum::ValueConverter(LSP::Data::CompletionItemKind))]
    property kind : CompletionItemKind?

    # A human-readable string with additional information
    # about this item, like type or symbol information.
    property detail : String?

    # A human-readable string that represents a doc-comment.
    property documentation : String | MarkupContent | Nil

    # Indicates if this item is deprecated.
    property deprecated : Bool?

    # Select this item when showing.
    #
    # *Note* that only one completion item can be selected and that the
    # tool / client decides which item that is. The rule is that the *first*
    # item of those that match best is selected.
    property preselect : Bool?

    # A string that should be used when comparing this item
    # with other items. When `falsy` the label is used.
    @[JSON::Field(key: "sortText")]
    property sort_text : String?

    # A string that should be used when filtering a set of
    # completion items. When `falsy` the label is used.
    @[JSON::Field(key: "filterText")]
    property filter_text : String?

    # A string that should be inserted into a document when selecting
    # this completion. When `falsy` the label is used.
    #
    # The `insertText` is subject to interpretation by the client side.
    # Some tools might not take the string literally. For example
    # VS Code when code complete is requested in this example
    # `con<cursor position>` and a completion item with an `insertText` of
    # `console` is provided it will only insert `sole`. Therefore it is
    # recommended to use `textEdit` instead since it avoids additional
    # client side interpretation.
    #
    # @deprecated Use textEdit instead.
    @[JSON::Field(key: "insertText")]
    property _insert_text : String?

    # The format of the insert text. The format applies to both the
    # `insertText` property and the `newText` property of a provided
    # `textEdit`.
    @[JSON::Field(key: "insertTextFormat", converter: Enum::ValueConverter(LSP::Data::InsertTextFormat))]
    property insert_text_format : InsertTextFormat?

    # An edit which is applied to a document when selecting this completion.
    # When an edit is provided the value of `insertText` is ignored.
    #
    # *Note:* The range of the edit must be a single line range and it must
    # contain the position at which completion has been requested.
    @[JSON::Field(key: "textEdit")]
    property text_edit : TextEdit?

    # An optional array of additional text edits that are applied when
    # selecting this completion. Edits must not overlap (including the same
    # insert position) with the main edit nor with themselves.
    #
    # Additional text edits should be used to change text unrelated to the
    # current cursor position (for example adding an import statement at the
    # top of the file if the completion item will insert an unqualified type).
    @[JSON::Field(key: "additionalTextEdits")]
    property additional_text_edits : Array(TextEdit) = [] of TextEdit

    # An optional set of characters that when pressed while this completion
    # is active will accept it first and then type that character.
    # *Note* that all commit characters should have `length=1` and that
    # superfluous characters will be ignored.
    @[JSON::Field(key: "commitCharacters")]
    property commit_characters : Array(String)? = [] of String

    # An optional command that is executed *after* inserting this completion.
    # *Note* that additional modifications to the current document should be
    # described with the additionalTextEdits-property.
    property command : Command?

    # An data entry field that is preserved on a completion item between
    # a completion and a completion resolve request.
    property data : JSON::Any?

    def initialize(
      @label = "",
      @kind = nil,
      @detail = nil,
      @documentation = nil,
      @deprecated = false,
      @preselect = false,
      @sort_text = nil,
      @filter_text = nil,
      @insert_text_format = nil,
      @text_edit = nil,
      @additional_text_edits = [] of TextEdit,
      @commit_characters = [] of String,
      @command = nil,
      @data = nil
    )
      @_insert_text = nil
    end
  end
end
