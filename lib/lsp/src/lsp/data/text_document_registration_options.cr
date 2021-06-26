require "json"

module LSP::Data
  struct TextDocumentRegistrationOptions
    include JSON::Serializable

    # A document selector to identify the scope of the registration. If set
    # to null the document selector provided on the client side will be used.
    @[JSON::Field(key: "documentSelector", emit_null: true)]
    property document_selector : Array(DocumentFilter)?
  end
end
