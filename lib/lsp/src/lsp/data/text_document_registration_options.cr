require "json"

module LSP::Data
  struct TextDocumentRegistrationOptions
    JSON.mapping({
      # A document selector to identify the scope of the registration. If set
      # to null the document selector provided on the client side will be used.
      document_selector: {
        type: Array(DocumentFilter)?,
        emit_null: true,
        key: "documentSelector"
      },
    })
  end
end
