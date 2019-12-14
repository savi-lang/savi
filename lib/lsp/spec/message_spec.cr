require "./spec_helper"

describe LSP::Message do
  describe ".from_json" do
    it "parses Cancel" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "method": "$/cancelRequest",
        "params": {
          "id": "example"
        }
      }
      EOF

      msg = msg.as LSP::Message::Cancel
      msg.params.id.should eq "example"
    end

    it "parses Initialize (minimal)" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "id": "example",
        "method": "initialize",
        "params": {
          "processId": 99,
          "rootUri": null,
          "capabilities": {}
        }
      }
      EOF

      msg = msg.as LSP::Message::Initialize
      msg.params.process_id.should eq 99
      msg.params._root_path.should eq nil
      msg.params.root_uri.should eq nil
      msg.params.options.should eq nil

      msg.params.capabilities.workspace.apply_edit.should eq false
      msg.params.capabilities.workspace.workspace_edit
        .document_changes.should eq false
      msg.params.capabilities.workspace.workspace_edit
        .resource_operations.should eq([] of String)
      msg.params.capabilities.workspace.workspace_edit
        .failure_handling.should eq "abort"
      msg.params.capabilities.workspace.did_change_configuration
        .dynamic_registration.should eq false
      msg.params.capabilities.workspace.did_change_watched_files
        .dynamic_registration.should eq false
      msg.params.capabilities.workspace.symbol
        .dynamic_registration.should eq false
      msg.params.capabilities.workspace.symbol.symbol_kind
        .value_set.should eq LSP::Data::SymbolKind.default
      msg.params.capabilities.workspace.execute_command
        .dynamic_registration.should eq false
      msg.params.capabilities.workspace.workspace_folders.should eq false
      msg.params.capabilities.workspace.configuration.should eq false

      msg.params.capabilities.text_document.synchronization
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.synchronization
        .will_save.should eq false
      msg.params.capabilities.text_document.synchronization
        .will_save_wait_until.should eq false
      msg.params.capabilities.text_document.synchronization
        .did_save.should eq false
      msg.params.capabilities.text_document.completion
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.completion.completion_item
        .snippet_support.should eq false
      msg.params.capabilities.text_document.completion.completion_item
        .commit_characters_support.should eq false
      msg.params.capabilities.text_document.completion.completion_item
        .documentation_format.should eq [] of String
      msg.params.capabilities.text_document.completion.completion_item
        .deprecated_support.should eq false
      msg.params.capabilities.text_document.completion.completion_item
        .preselect_support.should eq false
      msg.params.capabilities.text_document.completion.completion_item_kind
        .value_set.should eq LSP::Data::CompletionItemKind.default
      msg.params.capabilities.text_document.completion
        .context_support.should eq false
      msg.params.capabilities.text_document.hover
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.hover
        .content_format.should eq [] of String
      msg.params.capabilities.text_document.signature_help
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.signature_help.signature_information
        .documentation_format.should eq [] of String
      msg.params.capabilities.text_document.references
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.document_highlight
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.document_symbol
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.document_symbol.symbol_kind
        .value_set.should eq LSP::Data::SymbolKind.default
      msg.params.capabilities.text_document.document_symbol
        .hierarchical_document_symbol_support.should eq false
      msg.params.capabilities.text_document.formatting
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.range_formatting
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.on_type_formatting
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.definition
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.type_definition
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.implementation
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.code_action
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.code_action
        .code_action_literal_support.code_action_kind
        .value_set.should eq [] of String
      msg.params.capabilities.text_document.code_lens
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.document_link
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.color_provider
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.rename
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.rename
        .prepare_support.should eq false
      msg.params.capabilities.text_document.publish_diagnostics
        .related_information.should eq false
      msg.params.capabilities.text_document.folding_range
        .dynamic_registration.should eq false
      msg.params.capabilities.text_document.folding_range
        .range_limit.should eq 0
      msg.params.capabilities.text_document.folding_range
        .line_folding_only.should eq false

      msg.params.trace.should eq "off"

      msg.params.workspace_folders.should eq [] of LSP::Data::WorkspaceFolder
    end

    it "parses Initialize (maximal)" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "id": "example",
        "method": "initialize",
        "params": {
          "processId": 99,
          "rootPath": "/tmp/deprecated",
          "rootUri": "file:///tmp/example",
          "initializationOptions": {"foo": "bar"},
          "capabilities": {
            "workspace": {
              "applyEdit": true,
              "workspaceEdit": {
                "documentChanges": true,
                "resourceOperations": ["create", "delete", "rename"],
                "failureHandling": "transactional"
              },
              "didChangeConfiguration": { "dynamicRegistration": true },
              "didChangeWatchedFiles": { "dynamicRegistration": true },
              "symbol": {
                "dynamicRegistration": true,
                "symbolKind": {
                  "valueSet": ["Namespace"]
                }
              },
              "executeCommand": { "dynamicRegistration": true },
              "workspaceFolders": true,
              "configuration": true
            },
            "textDocument": {
              "synchronization": {
                "dynamicRegistration": true,
                "willSave": true,
                "willSaveWaitUntil": true,
                "didSave": true
              },
              "completion": {
                "dynamicRegistration": true,
                "completionItem": {
                  "snippetSupport": true,
                  "commitCharactersSupport": true,
                  "documentationFormat": ["markdown", "plaintext"],
                  "deprecatedSupport": true,
                  "preselectSupport": true
                },
                "completionItemKind": {
                  "valueSet": ["Folder"]
                },
                "contextSupport": true
              },
              "hover": {
                "dynamicRegistration": true,
                "contentFormat": ["markdown", "plaintext"]
              },
              "signatureHelp": {
                "dynamicRegistration": true,
                "signatureInformation": {
                  "documentationFormat": ["markdown", "plaintext"]
                }
              },
              "references": {
                "dynamicRegistration": true
              },
              "documentHighlight": {
                "dynamicRegistration": true
              },
              "documentSymbol": {
                "dynamicRegistration": true,
                "symbolKind": {
                  "valueSet": ["Namespace"]
                },
                "hierarchicalDocumentSymbolSupport": true
              },
              "formatting": {
                "dynamicRegistration": true
              },
              "rangeFormatting": {
                "dynamicRegistration": true
              },
              "onTypeFormatting": {
                "dynamicRegistration": true
              },
              "definition": {
                "dynamicRegistration": true
              },
              "typeDefinition": {
                "dynamicRegistration": true
              },
              "implementation": {
                "dynamicRegistration": true
              },
              "codeAction": {
                "dynamicRegistration": true,
                "codeActionLiteralSupport": {
                  "codeActionKind": {
                    "valueSet": ["exampleAction"]
                  }
                }
              },
              "codeLens": {
                "dynamicRegistration": true
              },
              "documentLink": {
                "dynamicRegistration": true
              },
              "colorProvider": {
                "dynamicRegistration": true
              },
              "rename": {
                "dynamicRegistration": true,
                "prepareSupport": true
              },
              "publishDiagnostics": {
                "relatedInformation": true
              },
              "foldingRange": {
                "dynamicRegistration": true,
                "rangeLimit": 500,
                "lineFoldingOnly": true
              }
            }
          },
          "trace": "verbose",
          "workspaceFolders": [
            {
              "uri": "file:///tmp/example/foo",
              "name": "foo"
            },
            {
              "uri": "file:///tmp/example/bar",
              "name": "bar"
            }
          ]
        }
      }
      EOF

      msg = msg.as LSP::Message::Initialize

      msg.params.process_id.should eq 99
      msg.params._root_path.should eq "/tmp/deprecated"
      msg.params.root_uri.as(URI).scheme.should eq "file"
      msg.params.root_uri.as(URI).path.should eq "/tmp/example"
      msg.params.options.should eq({"foo" => "bar"})

      msg.params.capabilities.workspace.apply_edit.should eq true
      msg.params.capabilities.workspace.workspace_edit
        .document_changes.should eq true
      msg.params.capabilities.workspace.workspace_edit
        .resource_operations.should eq(["create", "delete", "rename"])
      msg.params.capabilities.workspace.workspace_edit
        .failure_handling.should eq "transactional"
      msg.params.capabilities.workspace.did_change_configuration
        .dynamic_registration.should eq true
      msg.params.capabilities.workspace.did_change_watched_files
        .dynamic_registration.should eq true
      msg.params.capabilities.workspace.symbol
        .dynamic_registration.should eq true
      msg.params.capabilities.workspace.symbol.symbol_kind
        .value_set.should eq [LSP::Data::SymbolKind::Namespace]
      msg.params.capabilities.workspace.execute_command
        .dynamic_registration.should eq true
      msg.params.capabilities.workspace.workspace_folders.should eq true
      msg.params.capabilities.workspace.configuration.should eq true

      msg.params.capabilities.text_document.synchronization
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.synchronization
        .will_save.should eq true
      msg.params.capabilities.text_document.synchronization
        .will_save_wait_until.should eq true
      msg.params.capabilities.text_document.synchronization
        .did_save.should eq true
      msg.params.capabilities.text_document.completion
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.completion.completion_item
        .snippet_support.should eq true
      msg.params.capabilities.text_document.completion.completion_item
        .commit_characters_support.should eq true
      msg.params.capabilities.text_document.completion.completion_item
        .documentation_format.should eq ["markdown", "plaintext"]
      msg.params.capabilities.text_document.completion.completion_item
        .deprecated_support.should eq true
      msg.params.capabilities.text_document.completion.completion_item
        .preselect_support.should eq true
      msg.params.capabilities.text_document.completion.completion_item_kind
        .value_set.should eq [LSP::Data::CompletionItemKind::Folder]
      msg.params.capabilities.text_document.completion
        .context_support.should eq true
      msg.params.capabilities.text_document.hover
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.hover
        .content_format.should eq ["markdown", "plaintext"]
      msg.params.capabilities.text_document.signature_help
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.signature_help.signature_information
        .documentation_format.should eq ["markdown", "plaintext"]
      msg.params.capabilities.text_document.references
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.document_highlight
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.document_symbol
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.document_symbol.symbol_kind
        .value_set.should eq [LSP::Data::SymbolKind::Namespace]
      msg.params.capabilities.text_document.document_symbol
        .hierarchical_document_symbol_support.should eq true
      msg.params.capabilities.text_document.formatting
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.range_formatting
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.on_type_formatting
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.definition
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.type_definition
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.implementation
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.code_action
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.code_action
        .code_action_literal_support.code_action_kind
        .value_set.should eq ["exampleAction"]
      msg.params.capabilities.text_document.code_lens
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.document_link
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.color_provider
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.rename
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.rename
        .prepare_support.should eq true
      msg.params.capabilities.text_document.publish_diagnostics
        .related_information.should eq true
      msg.params.capabilities.text_document.folding_range
        .dynamic_registration.should eq true
      msg.params.capabilities.text_document.folding_range
        .range_limit.should eq 500
      msg.params.capabilities.text_document.folding_range
        .line_folding_only.should eq true

      msg.params.trace.should eq "verbose"

      msg.params.workspace_folders.size.should eq 2
      msg.params.workspace_folders[0].uri.scheme.should eq "file"
      msg.params.workspace_folders[0].uri.path.should eq "/tmp/example/foo"
      msg.params.workspace_folders[0].name.should eq "foo"
      msg.params.workspace_folders[1].uri.scheme.should eq "file"
      msg.params.workspace_folders[1].uri.path.should eq "/tmp/example/bar"
      msg.params.workspace_folders[1].name.should eq "bar"
    end

    it "parses Initialized" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": {}
      }
      EOF

      msg = msg.as LSP::Message::Initialized
    end

    it "parses Shutdown" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "id": "example",
        "method": "shutdown"
      }
      EOF

      msg = msg.as LSP::Message::Shutdown
    end

    it "parses Exit" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "method": "exit"
      }
      EOF

      msg = msg.as LSP::Message::Exit
    end

    it "parses ShowMessageRequest::Response" do
      req = LSP::Message::ShowMessageRequest.new("example")
      reqs = {} of (String | Int64) => LSP::Message::AnyRequest
      reqs["example"] = req

      msg = LSP::Message.from_json <<-EOF, reqs
      {
        "jsonrpc": "2.0",
        "id": "example",
        "result": {
          "title": "Hello!"
        }
      }
      EOF

      msg = msg.as LSP::Message::ShowMessageRequest::Response
      msg.request.should eq req
      msg.result.as(LSP::Data::MessageActionItem).title.should eq "Hello!"
    end

    it "parses didChangeConfiguration" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "method": "workspace/didChangeConfiguration",
        "params": {
          "settings": {
            "my-language": {
              "foo": "bar"
            }
          }
        }
      }
      EOF

      msg = msg.as LSP::Message::DidChangeConfiguration
      msg.params.settings.should eq({"my-language" => {"foo" => "bar"}})
    end

    it "parses DidOpen" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": {
          "textDocument": {
            "uri": "file:///tmp/example/foo",
            "languageId": "crystal",
            "version": 42,
            "text": "class Foo; end"
          }
        }
      }
      EOF

      msg = msg.as LSP::Message::DidOpen
      msg.params.text_document.uri.scheme.should eq "file"
      msg.params.text_document.uri.path.should eq "/tmp/example/foo"
      msg.params.text_document.language_id.should eq "crystal"
      msg.params.text_document.version.should eq 42
      msg.params.text_document.text.should eq "class Foo; end"
    end

    it "parses DidChange (full document)" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "method": "textDocument/didChange",
        "params": {
          "textDocument": {
            "uri": "file:///tmp/example/foo",
            "version": 42
          },
          "contentChanges": [
            {
              "text": "class Foo; end"
            }
          ]
        }
      }
      EOF

      msg = msg.as LSP::Message::DidChange
      msg.params.text_document.uri.scheme.should eq "file"
      msg.params.text_document.uri.path.should eq "/tmp/example/foo"
      msg.params.text_document.version.should eq 42
      msg.params.content_changes[0].text.should eq "class Foo; end"
    end

    it "parses DidChange (ranged)" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "method": "textDocument/didChange",
        "params": {
          "textDocument": {
            "uri": "file:///tmp/example/foo",
            "version": 42
          },
          "contentChanges": [
            {
              "range": {
                "start": { "line": 4, "character": 2 },
                "end": { "line": 4, "character": 5 }
              },
              "rangeLength": 3,
              "text": "foo"
            }
          ]
        }
      }
      EOF

      msg = msg.as LSP::Message::DidChange
      msg.params.text_document.uri.scheme.should eq "file"
      msg.params.text_document.uri.path.should eq "/tmp/example/foo"
      msg.params.text_document.version.should eq 42
      range = msg.params.content_changes[0].range.as(LSP::Data::Range)
      range.start.line.should eq 4
      range.start.character.should eq 2
      range.finish.line.should eq 4
      range.finish.character.should eq 5
      msg.params.content_changes[0].range_length.should eq 3
      msg.params.content_changes[0].text.should eq "foo"
    end

    it "parses WillSave" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "method": "textDocument/willSave",
        "params": {
          "textDocument": {
            "uri": "file:///tmp/example/foo"
          },
          "reason": 2
        }
      }
      EOF

      msg = msg.as LSP::Message::WillSave
      msg.params.text_document.uri.scheme.should eq "file"
      msg.params.text_document.uri.path.should eq "/tmp/example/foo"
      msg.params.reason.should eq LSP::Data::TextDocumentSaveReason::AfterDelay
    end

    it "parses DidSave" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "method": "textDocument/didSave",
        "params": {
          "textDocument": {
            "uri": "file:///tmp/example/foo"
          },
          "text": "class Foo; end"
        }
      }
      EOF

      msg = msg.as LSP::Message::DidSave
      msg.params.text_document.uri.scheme.should eq "file"
      msg.params.text_document.uri.path.should eq "/tmp/example/foo"
      msg.params.text.should eq "class Foo; end"
    end

    it "parses DidClose" do
      msg = LSP::Message.from_json <<-EOF
      {
        "jsonrpc": "2.0",
        "method": "textDocument/didClose",
        "params": {
          "textDocument": {
            "uri": "file:///tmp/example/foo"
          }
        }
      }
      EOF

      msg = msg.as LSP::Message::DidClose
      msg.params.text_document.uri.scheme.should eq "file"
      msg.params.text_document.uri.path.should eq "/tmp/example/foo"
    end

    it "parses Completion" do
      msg = LSP::Message.from_json <<-EOF
      {
        "method": "textDocument/completion",
        "jsonrpc": "2.0",
        "id": "example",
        "params": {
          "textDocument": {
            "uri": "file:///tmp/example/foo"
          },
          "position": {
            "line": 4,
            "character": 2
          },
          "context": {
            "triggerKind": 2,
            "triggerCharacter": "."
          }
        }
      }
      EOF

      msg = msg.as LSP::Message::Completion
      msg.id.should eq "example"
      msg.params.text_document.uri.scheme.should eq "file"
      msg.params.text_document.uri.path.should eq "/tmp/example/foo"
      msg.params.position.line.should eq 4
      msg.params.position.character.should eq 2
      msg.params.context.as(LSP::Data::CompletionContext).try do |context|
        context.trigger_kind.should eq \
          LSP::Data::CompletionTriggerKind::TriggerCharacter
        context.trigger_character.should eq "."
      end
    end

    it "parses CompletionItemResolve" do
      msg = LSP::Message.from_json <<-EOF
      {
        "method": "completionItem/resolve",
        "jsonrpc": "2.0",
        "id": "example",
        "params": {
          "label": "open",
          "kind": 3,
          "detail": "File.open()",
          "documentation": {
            "kind": "markdown",
            "value": "..."
          },
          "deprecated": true,
          "preselect": true,
          "sortText": "File.open",
          "filterText": "File.open",
          "insertTextFormat": 2,
          "textEdit": {
            "range": {
              "start": {
                "line": 4,
                "character": 2
              },
              "end": {
                "line": 4,
                "character": 3
              }
            },
            "newText": ".open"
          },
          "additionalTextEdits": [
            {
              "range": {
                "start": {
                  "line": 1,
                  "character": 2
                },
                "end": {
                  "line": 1,
                  "character": 2
                }
              },
              "newText": "require 'file'\\n"
            }
          ],
          "commitCharacters": [
            "("
          ],
          "command": {
            "title": "Example",
            "command": "example",
            "arguments": [
              "File",
              "open"
            ]
          },
          "data": {
            "foo": "bar"
          }
        }
      }
      EOF

      msg = msg.as LSP::Message::CompletionItemResolve
      msg.id.should eq "example"
      msg.params.label.should eq "open"
      msg.params.kind.should eq LSP::Data::CompletionItemKind::Function
      msg.params.detail.should eq "File.open()"
      msg.params.documentation.as(LSP::Data::MarkupContent).try do |doc|
        doc.kind.should eq "markdown"
        doc.value.should eq "..."
      end
      msg.params.deprecated.should eq true
      msg.params.preselect.should eq true
      msg.params.sort_text.should eq "File.open"
      msg.params.filter_text.should eq "File.open"
      msg.params.insert_text_format.should eq LSP::Data::InsertTextFormat::Snippet
      msg.params.text_edit.as(LSP::Data::TextEdit).tap do |edit|
        edit.range.start.line.should eq 4
        edit.range.start.character.should eq 2
        edit.range.finish.line.should eq 4
        edit.range.finish.character.should eq 3
        edit.new_text.should eq ".open"
      end
      msg.params.additional_text_edits[0].tap do |edit|
        edit.range.start.line.should eq 1
        edit.range.start.character.should eq 2
        edit.range.finish.line.should eq 1
        edit.range.finish.character.should eq 2
        edit.new_text.should eq "require 'file'\n"
      end
      msg.params.commit_characters.should eq ["("]
      msg.params.command.as(LSP::Data::Command).try do |cmd|
        cmd.title.should eq "Example"
        cmd.command.should eq "example"
        cmd.arguments[0].should eq JSON::Any.new("File")
        cmd.arguments[1].should eq JSON::Any.new("open")
        cmd
      end
      msg.params.data.should eq JSON::Any.new({"foo" => JSON::Any.new("bar")})
    end

    it "parses Hover" do
      msg = LSP::Message.from_json <<-EOF
      {
        "method": "textDocument/hover",
        "jsonrpc": "2.0",
        "id": "example",
        "params": {
          "textDocument": {
            "uri": "file:///tmp/example/foo"
          },
          "position": {
            "line": 4,
            "character": 2
          }
        }
      }
      EOF

      msg = msg.as LSP::Message::Hover
      msg.id.should eq "example"
      msg.params.text_document.uri.scheme.should eq "file"
      msg.params.text_document.uri.path.should eq "/tmp/example/foo"
      msg.params.position.line.should eq 4
      msg.params.position.character.should eq 2
    end

    it "parses SignatureHelp" do
      msg = LSP::Message.from_json <<-EOF
      {
        "method": "textDocument/signatureHelp",
        "jsonrpc": "2.0",
        "id": "example",
        "params": {
          "textDocument": {
            "uri": "file:///tmp/example/foo"
          },
          "position": {
            "line": 4,
            "character": 2
          }
        }
      }
      EOF

      msg = msg.as LSP::Message::SignatureHelp
      msg.id.should eq "example"
      msg.params.text_document.uri.scheme.should eq "file"
      msg.params.text_document.uri.path.should eq "/tmp/example/foo"
      msg.params.position.line.should eq 4
      msg.params.position.character.should eq 2
    end
  end

  describe "Any.to_json" do
    it "builds Cancel" do
      msg = LSP::Message::Cancel.new
      msg.params.id = "example"

      msg.to_pretty_json.should eq <<-EOF
      {
        "method": "$/cancelRequest",
        "jsonrpc": "2.0",
        "params": {
          "id": "example"
        }
      }
      EOF
    end

    it "builds Initialize::Response (minimal)" do
      req = LSP::Message::Initialize.new "example"
      msg = req.new_response

      msg.to_pretty_json.should eq <<-EOF
      {
        "jsonrpc": "2.0",
        "id": "example",
        "result": {
          "capabilities": {
            "textDocumentSync": {
              "openClose": false,
              "change": 0,
              "willSave": false,
              "willSaveWaitUntil": false
            },
            "hoverProvider": false,
            "definitionProvider": false,
            "typeDefinitionProvider": false,
            "implementationProvider": false,
            "referencesProvider": false,
            "documentHighlightProvider": false,
            "documentSymbolProvider": false,
            "workspaceSymbolProvider": false,
            "codeActionProvider": false,
            "documentFormattingProvider": false,
            "documentRangeFormattingProvider": false,
            "renameProvider": false,
            "colorProvider": false,
            "foldingRangeProvider": false,
            "workspace": {
              "workspaceFolders": {
                "supported": false,
                "changeNotifications": false
              }
            },
            "experimental": {}
          }
        }
      }
      EOF
    end

    it "builds Initialize::Response (maximal)" do
      req = LSP::Message::Initialize.new "example"
      msg = req.new_response

      msg.result.capabilities.text_document_sync.open_close = true
      msg.result.capabilities.text_document_sync.change =
        LSP::Data::TextDocumentSyncKind::Incremental
      msg.result.capabilities.text_document_sync.will_save = true
      msg.result.capabilities.text_document_sync.will_save_wait_until = true
      msg.result.capabilities.text_document_sync.save =
        LSP::Data::ServerCapabilities::SaveOptions.new(true)

      msg.result.capabilities.hover_provider = true

      msg.result.capabilities.completion_provider =
        LSP::Data::ServerCapabilities::CompletionOptions.new(true, ["=", "."])

      msg.result.capabilities.signature_help_provider =
        LSP::Data::ServerCapabilities::SignatureHelpOptions.new(["("])

      msg.result.capabilities.definition_provider = true

      msg.result.capabilities.type_definition_provider =
        LSP::Data::ServerCapabilities::StaticRegistrationOptions.new([
          LSP::Data::DocumentFilter.new("crystal", "file", "*.cr")
        ], "reg")

      msg.result.capabilities.implementation_provider =
        LSP::Data::ServerCapabilities::StaticRegistrationOptions.new([
          LSP::Data::DocumentFilter.new("crystal", "file", "*.cr")
        ], "reg")

      msg.result.capabilities.references_provider = true

      msg.result.capabilities.document_highlight_provider = true

      msg.result.capabilities.document_symbol_provider = true

      msg.result.capabilities.workspace_symbol_provider = true

      msg.result.capabilities.code_action_provider =
        LSP::Data::ServerCapabilities::CodeActionOptions.new([
          "quickfix",
          "refactor",
          "source",
        ])

      msg.result.capabilities.code_lens_provider =
        LSP::Data::ServerCapabilities::CodeLensOptions.new(true)

      msg.result.capabilities.document_formatting_provider = true

      msg.result.capabilities.document_range_formatting_provider = true

      msg.result.capabilities.document_on_type_formatting_provider =
        LSP::Data::ServerCapabilities::DocumentOnTypeFormattingOptions.new(
          "}",
          ")",
          ":",
        )

      msg.result.capabilities.rename_provider =
        LSP::Data::ServerCapabilities::RenameOptions.new(true)

      msg.result.capabilities.document_link_provider =
        LSP::Data::ServerCapabilities::DocumentLinkOptions.new(true)

      msg.result.capabilities.color_provider =
        LSP::Data::ServerCapabilities::StaticRegistrationOptions.new([
          LSP::Data::DocumentFilter.new("crystal", "file", "*.cr")
        ], "reg")

      msg.result.capabilities.folding_range_provider =
        LSP::Data::ServerCapabilities::StaticRegistrationOptions.new([
          LSP::Data::DocumentFilter.new("crystal", "file", "*.cr")
        ], "reg")

      msg.result.capabilities.execute_command_provider =
        LSP::Data::ServerCapabilities::ExecuteCommandOptions.new(["x", "y"])

      msg.result.capabilities.workspace.workspace_folders.supported = true
      msg.result.capabilities.workspace.workspace_folders.change_notifications = "reg"

      msg.to_pretty_json.should eq <<-EOF
      {
        "jsonrpc": "2.0",
        "id": "example",
        "result": {
          "capabilities": {
            "textDocumentSync": {
              "openClose": true,
              "change": 2,
              "willSave": true,
              "willSaveWaitUntil": true,
              "save": {
                "includeText": true
              }
            },
            "hoverProvider": true,
            "completionProvider": {
              "resolveProvider": true,
              "triggerCharacters": [
                "=",
                "."
              ]
            },
            "signatureHelpProvider": {
              "triggerCharacters": [
                "("
              ]
            },
            "definitionProvider": true,
            "typeDefinitionProvider": {
              "documentSelector": [
                {
                  "language": "crystal",
                  "scheme": "file",
                  "pattern": "*.cr"
                }
              ],
              "id": "reg"
            },
            "implementationProvider": {
              "documentSelector": [
                {
                  "language": "crystal",
                  "scheme": "file",
                  "pattern": "*.cr"
                }
              ],
              "id": "reg"
            },
            "referencesProvider": true,
            "documentHighlightProvider": true,
            "documentSymbolProvider": true,
            "workspaceSymbolProvider": true,
            "codeActionProvider": {
              "codeActionKinds": [
                "quickfix",
                "refactor",
                "source"
              ]
            },
            "codeLensProvider": {
              "resolveProvider": true
            },
            "documentFormattingProvider": true,
            "documentRangeFormattingProvider": true,
            "documentOnTypeFormattingProvider": {
              "firstTriggerCharacter": "}",
              "moreTriggerCharacter": [
                ")",
                ":"
              ]
            },
            "renameProvider": {
              "prepareProvider": true
            },
            "documentLinkProvider": {
              "resolveProvider": true
            },
            "colorProvider": {
              "documentSelector": [
                {
                  "language": "crystal",
                  "scheme": "file",
                  "pattern": "*.cr"
                }
              ],
              "id": "reg"
            },
            "foldingRangeProvider": {
              "documentSelector": [
                {
                  "language": "crystal",
                  "scheme": "file",
                  "pattern": "*.cr"
                }
              ],
              "id": "reg"
            },
            "executeCommandProvider": {
              "commands": [
                "x",
                "y"
              ]
            },
            "workspace": {
              "workspaceFolders": {
                "supported": true,
                "changeNotifications": "reg"
              }
            },
            "experimental": {}
          }
        }
      }
      EOF
    end

    it "builds Shutdown::Response" do
      req = LSP::Message::Shutdown.new "example"
      msg = req.new_response

      msg.to_pretty_json.should eq <<-EOF
      {
        "jsonrpc": "2.0",
        "id": "example",
        "result": null
      }
      EOF
    end

    it "builds ShowMessage" do
      msg = LSP::Message::ShowMessage.new
      msg.params.type = LSP::Data::MessageType::Info
      msg.params.message = "Hello, World!"

      msg.to_pretty_json.should eq <<-EOF
      {
        "method": "window/showMessage",
        "jsonrpc": "2.0",
        "params": {
          "type": 3,
          "message": "Hello, World!"
        }
      }
      EOF
    end

    it "builds ShowMessageRequest" do
      msg = LSP::Message::ShowMessageRequest.new("example")
      msg.params.type = LSP::Data::MessageType::Info
      msg.params.message = "Hello, World!"
      msg.params.actions << LSP::Data::MessageActionItem.new("Hello!")
      msg.params.actions << LSP::Data::MessageActionItem.new("Goodbye!")

      msg.to_pretty_json.should eq <<-EOF
      {
        "method": "window/showMessageRequest",
        "jsonrpc": "2.0",
        "id": "example",
        "params": {
          "type": 3,
          "message": "Hello, World!",
          "actions": [
            {
              "title": "Hello!"
            },
            {
              "title": "Goodbye!"
            }
          ]
        }
      }
      EOF
    end

    it "builds LogMessage" do
      msg = LSP::Message::LogMessage.new
      msg.params.type = LSP::Data::MessageType::Info
      msg.params.message = "Hello, World!"

      msg.to_pretty_json.should eq <<-EOF
      {
        "method": "window/logMessage",
        "jsonrpc": "2.0",
        "params": {
          "type": 3,
          "message": "Hello, World!"
        }
      }
      EOF
    end

    it "builds Telemetry" do
      msg = LSP::Message::Telemetry.new \
        JSON::Any.new({"foo" => JSON::Any.new("bar")})

      msg.to_pretty_json.should eq <<-EOF
      {
        "method": "telemetry/event",
        "jsonrpc": "2.0",
        "params": {
          "foo": "bar"
        }
      }
      EOF
    end

    it "builds PublishDiagnostics" do
      msg = LSP::Message::PublishDiagnostics.new
      msg.params.uri = URI.new("file", "/tmp/example/foo")
      msg.params.diagnostics << LSP::Data::Diagnostic.new.try do |diag|
        diag.range.start.line = 4
        diag.range.start.character = 2
        diag.range.finish.line = 4
        diag.range.finish.character = 5
        diag.severity = LSP::Data::Diagnostic::Severity::Warning
        diag.code = "unused-assignment"
        diag.source = "crystal"
        diag.message = "Unused assignment to reference named 'foo'"
        diag.related_information <<
        LSP::Data::Diagnostic::RelatedInformation.new.try do |info|
          info.location.uri = URI.new("file", "/tmp/example/foo")
          info.location.range.start.line = 5
          info.location.range.start.character = 0
          info.location.range.finish.line = 5
          info.location.range.finish.character = 2
          info.message = "End of scope is here"
          info
        end
        diag
      end

      msg.to_pretty_json.should eq <<-EOF
      {
        "method": "textDocument/publishDiagnostics",
        "jsonrpc": "2.0",
        "params": {
          "uri": "file:///tmp/example/foo",
          "diagnostics": [
            {
              "range": {
                "start": {
                  "line": 4,
                  "character": 2
                },
                "end": {
                  "line": 4,
                  "character": 5
                }
              },
              "severity": 2,
              "code": "unused-assignment",
              "source": "crystal",
              "message": "Unused assignment to reference named 'foo'",
              "relatedInformation": [
                {
                  "location": {
                    "uri": "file:///tmp/example/foo",
                    "range": {
                      "start": {
                        "line": 5,
                        "character": 0
                      },
                      "end": {
                        "line": 5,
                        "character": 2
                      }
                    }
                  },
                  "message": "End of scope is here"
                }
              ]
            }
          ]
        }
      }
      EOF
    end

    it "builds Completion::Response" do
      req = LSP::Message::Completion.new "example"
      msg = req.new_response
      msg.result.is_incomplete = true
      msg.result.items << LSP::Data::CompletionItem.new.try do |item|
        item.label = "open"
        item.kind = LSP::Data::CompletionItemKind::Function
        item.detail = "File.open()"
        item.documentation = LSP::Data::MarkupContent.new("markdown", "...")
        item.deprecated = true
        item.preselect = true
        item.sort_text = "File.open"
        item.filter_text = "File.open"
        item.insert_text_format = LSP::Data::InsertTextFormat::Snippet
        item.text_edit = LSP::Data::TextEdit.new.try do |edit|
          edit.range.start.line = 4
          edit.range.start.character = 2
          edit.range.finish.line = 4
          edit.range.finish.character = 3
          edit.new_text = ".open"
          edit
        end
        item.additional_text_edits << LSP::Data::TextEdit.new.try do |edit|
          edit.range.start.line = 1
          edit.range.start.character = 2
          edit.range.finish.line = 1
          edit.range.finish.character = 2
          edit.new_text = "require 'file'\n"
          edit
        end
        item.commit_characters = ["("]
        item.command = LSP::Data::Command.new.try do |cmd|
          cmd.title = "Example"
          cmd.command = "example"
          cmd.arguments << JSON::Any.new("File")
          cmd.arguments << JSON::Any.new("open")
          cmd
        end
        item.data = JSON::Any.new({"foo" => JSON::Any.new("bar")})
        item
      end

      msg.to_pretty_json.should eq <<-EOF
      {
        "jsonrpc": "2.0",
        "id": "example",
        "result": {
          "isIncomplete": true,
          "items": [
            {
              "label": "open",
              "kind": 3,
              "detail": "File.open()",
              "documentation": {
                "kind": "markdown",
                "value": "..."
              },
              "deprecated": true,
              "preselect": true,
              "sortText": "File.open",
              "filterText": "File.open",
              "insertTextFormat": 2,
              "textEdit": {
                "range": {
                  "start": {
                    "line": 4,
                    "character": 2
                  },
                  "end": {
                    "line": 4,
                    "character": 3
                  }
                },
                "newText": ".open"
              },
              "additionalTextEdits": [
                {
                  "range": {
                    "start": {
                      "line": 1,
                      "character": 2
                    },
                    "end": {
                      "line": 1,
                      "character": 2
                    }
                  },
                  "newText": "require 'file'\\n"
                }
              ],
              "commitCharacters": [
                "("
              ],
              "command": {
                "title": "Example",
                "command": "example",
                "arguments": [
                  "File",
                  "open"
                ]
              },
              "data": {
                "foo": "bar"
              }
            }
          ]
        }
      }
      EOF
    end

    it "builds CompletionItemResolve::Response" do
      req = LSP::Message::CompletionItemResolve.new "example"
      msg = req.new_response
      msg.result = LSP::Data::CompletionItem.new.try do |item|
        item.label = "open"
        item.kind = LSP::Data::CompletionItemKind::Function
        item.detail = "File.open()"
        item.documentation = LSP::Data::MarkupContent.new("markdown", "...")
        item.deprecated = true
        item.preselect = true
        item.sort_text = "File.open"
        item.filter_text = "File.open"
        item.insert_text_format = LSP::Data::InsertTextFormat::Snippet
        item.text_edit = LSP::Data::TextEdit.new.try do |edit|
          edit.range.start.line = 4
          edit.range.start.character = 2
          edit.range.finish.line = 4
          edit.range.finish.character = 3
          edit.new_text = ".open"
          edit
        end
        item.additional_text_edits << LSP::Data::TextEdit.new.try do |edit|
          edit.range.start.line = 1
          edit.range.start.character = 2
          edit.range.finish.line = 1
          edit.range.finish.character = 2
          edit.new_text = "require 'file'\n"
          edit
        end
        item.commit_characters = ["("]
        item.command = LSP::Data::Command.new.try do |cmd|
          cmd.title = "Example"
          cmd.command = "example"
          cmd.arguments << JSON::Any.new("File")
          cmd.arguments << JSON::Any.new("open")
          cmd
        end
        item.data = JSON::Any.new({"foo" => JSON::Any.new("bar")})
        item
      end

      msg.to_pretty_json.should eq <<-EOF
      {
        "jsonrpc": "2.0",
        "id": "example",
        "result": {
          "label": "open",
          "kind": 3,
          "detail": "File.open()",
          "documentation": {
            "kind": "markdown",
            "value": "..."
          },
          "deprecated": true,
          "preselect": true,
          "sortText": "File.open",
          "filterText": "File.open",
          "insertTextFormat": 2,
          "textEdit": {
            "range": {
              "start": {
                "line": 4,
                "character": 2
              },
              "end": {
                "line": 4,
                "character": 3
              }
            },
            "newText": ".open"
          },
          "additionalTextEdits": [
            {
              "range": {
                "start": {
                  "line": 1,
                  "character": 2
                },
                "end": {
                  "line": 1,
                  "character": 2
                }
              },
              "newText": "require 'file'\\n"
            }
          ],
          "commitCharacters": [
            "("
          ],
          "command": {
            "title": "Example",
            "command": "example",
            "arguments": [
              "File",
              "open"
            ]
          },
          "data": {
            "foo": "bar"
          }
        }
      }
      EOF
    end

    it "builds Hover::Response" do
      req = LSP::Message::Hover.new "example"
      msg = req.new_response
      msg.result.contents = LSP::Data::MarkupContent.new("markdown", "...")
      msg.result.range = LSP::Data::Range.new.try do |range|
        range.start.line = 4
        range.start.character = 2
        range.finish.line = 4
        range.finish.character = 5
        range
      end

      msg.to_pretty_json.should eq <<-EOF
      {
        "jsonrpc": "2.0",
        "id": "example",
        "result": {
          "contents": {
            "kind": "markdown",
            "value": "..."
          },
          "range": {
            "start": {
              "line": 4,
              "character": 2
            },
            "end": {
              "line": 4,
              "character": 5
            }
          }
        }
      }
      EOF
    end

    it "builds SignatureHelp::Response" do
      req = LSP::Message::SignatureHelp.new "example"
      msg = req.new_response
      msg.result.signatures << LSP::Data::SignatureInformation.new.try do |sig|
        sig.label = "open(2)"
        sig.documentation = LSP::Data::MarkupContent.new("markdown", "...")
        sig.parameters << LSP::Data::ParameterInformation.new.try do |param|
          param.label = "filename"
          param.documentation = LSP::Data::MarkupContent.new("markdown", "...")
          param
        end
        sig.parameters << LSP::Data::ParameterInformation.new.try do |param|
          param.label = "mode"
          param.documentation = LSP::Data::MarkupContent.new("markdown", "...")
          param
        end
        sig
      end
      msg.result.active_signature = 0
      msg.result.active_parameter = 1

      msg.to_pretty_json.should eq <<-EOF
      {
        "jsonrpc": "2.0",
        "id": "example",
        "result": {
          "signatures": [
            {
              "label": "open(2)",
              "documentation": {
                "kind": "markdown",
                "value": "..."
              },
              "parameters": [
                {
                  "label": "filename",
                  "documentation": {
                    "kind": "markdown",
                    "value": "..."
                  }
                },
                {
                  "label": "mode",
                  "documentation": {
                    "kind": "markdown",
                    "value": "..."
                  }
                }
              ]
            }
          ],
          "activeSignature": 0,
          "activeParameter": 1
        }
      }
      EOF
    end
  end
end
