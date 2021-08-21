require "json"
require "uri"

module LSP::Message
  macro def_notification(method, has_params = true)
    include JSON::Serializable

    @[JSON::Field(converter: LSP::JSONUtil::SpecificString.new({{method}}))]
    property method : String

    @[JSON::Field(converter: LSP::JSONUtil::SpecificString.new("2.0"))]
    property jsonrpc : String

    {% if has_params %}
    property params : Params
    {% end %}

    def initialize({% if has_params %} @params = Params.new {% end %})
      @method = {{method}}
      @jsonrpc = "2.0"
    end

    def self.method; {{method}} end
  end

  macro def_request(method, has_params = true)
    include JSON::Serializable

    @[JSON::Field(converter: LSP::JSONUtil::SpecificString.new({{method}}))]
    property method : String
    @[JSON::Field(converter: LSP::JSONUtil::SpecificString.new("2.0"))]
    property jsonrpc : String
    property id : Int64 | String
    {% if has_params %}
    property params :  Params
    {% end %}

    def initialize(@id{% if has_params %}, @params = Params.new {% end %})
      @method = {{method}}
      @jsonrpc = "2.0"
    end

    alias SelfType = self

    struct Response
      Message.def_response(SelfType)
    end

    struct ErrorResponse
      Message.def_error_response(SelfType)
    end

    def self.method; {{method}} end

    def self.empty_result; Result.new end

    def response_from_json(input)
      res = Response.from_json(input)
      res.request = self
      res
    end

    def new_response
      res = Response.new(@id)
      res.request = self
      res
    end

    def error_response_from_json(input)
      res = ErrorResponse.from_json(input)
      res.request = self
      res
    end

    def new_error_response
      res = ErrorResponse.new(@id, Data::ResponseError(ErrorData).new)
      res.request = self
      res
    end
  end

  macro def_response(request_class)
    include JSON::Serializable

    @[JSON::Field(ignore: true)]
    property request : {{request_class}}?

    @[JSON::Field(converter: LSP::JSONUtil::SpecificString.new("2.0"))]
    property jsonrpc : String
    property id : Int64 | String | Nil
    @[JSON::Field(emit_null: true)]
    property result : Result

    def initialize(@id, @result : Result = {{request_class}}.empty_result)
      @jsonrpc = "2.0"
    end

    def self.method; nil end
  end

  macro def_error_response(request_class)
    include JSON::Serializable

    @[JSON::Field(ignore: true)]
    property request : {{request_class}}?

    @[JSON::Field(converter: LSP::JSONUtil::SpecificString.new("2.0"))]
    property jsonrpc : String
    property id : Int64 | String | Nil
    property error : Data::ResponseError(ErrorData)?

    def initialize(@id, @error : Data::ResponseError(ErrorData))
      @jsonrpc = "2.0"
    end

    def self.method; nil end
  end

  def self.from_json(input, outstanding = {} of (String | Int64) => AnyRequest)
    parser = JSON::PullParser.new(input)
    method : String? = nil
    id : (Int64 | String)? = nil
    is_error = false
    parser.read_object do |key|
      case key
      when "method"; method = parser.read_string
      when "id"    ; id = parser.read?(Int64) || parser.read_string
      when "error" ; is_error = true; parser.skip
      else           parser.skip
      end
    end

    {% if true %}
      case method
      when nil
        req = outstanding.delete(id)
        if req
          if is_error
            req.error_response_from_json(input)
          else
            req.response_from_json(input)
          end
        else
          if is_error
            GenericErrorResponse.from_json(input)
          else
            GenericResponse.from_json(input)
          end
        end
      {% for t in AnyMethod.union_types %}
        when {{ t }}.method; {{ t }}.from_json(input)
      {% end %}
      else raise "unrecognized JSON RPC method: #{method}"
      end.as(Any)
    {% end %}
  end

  alias Any = AnyIn | AnyOut
  alias AnyIn = AnyInNotification | AnyInRequest | AnyInResponse | AnyInErrorResponse
  alias AnyOut = AnyOutNotification | AnyOutRequest | AnyOutResponse | AnyOutErrorResponse

  alias AnyMethod = AnyInMethod | AnyOutMethod
  alias AnyInMethod = AnyInNotification | AnyInRequest
  alias AnyOutMethod = AnyOutNotification | AnyOutRequest

  alias AnyRequest = AnyInRequest | AnyOutRequest

  alias AnyInNotification = Cancel |
                            Initialized |
                            Exit |
                            DidChangeConfiguration |
                            DidOpen |
                            DidChange |
                            WillSave |
                            DidSave |
                            DidClose

  alias AnyInRequest = Initialize |
                       Shutdown |
                       Completion |
                       CompletionItemResolve |
                       Hover |
                       SignatureHelp |
                       Formatting |
                       RangeFormatting |
                       OnTypeFormatting

  alias AnyInResponse = GenericResponse |
                        ShowMessageRequest::Response

  alias AnyInErrorResponse = GenericErrorResponse |
                             ShowMessageRequest::ErrorResponse

  alias AnyOutNotification = Cancel |
                             ShowMessage |
                             PublishDiagnostics

  alias AnyOutResponse = GenericResponse |
                         Initialize::Response |
                         Shutdown::Response |
                         Completion::Response |
                         CompletionItemResolve::Response |
                         Hover::Response |
                         SignatureHelp::Response |
                         Formatting::Response |
                         RangeFormatting::Response |
                         OnTypeFormatting::Response

  alias AnyOutErrorResponse = GenericErrorResponse |
                              Initialize::ErrorResponse |
                              Shutdown::ErrorResponse |
                              Completion::ErrorResponse |
                              CompletionItemResolve::ErrorResponse |
                              Hover::ErrorResponse |
                              SignatureHelp::ErrorResponse |
                              Formatting::ErrorResponse |
                              RangeFormatting::ErrorResponse |
                              OnTypeFormatting::ErrorResponse

  alias AnyOutRequest = ShowMessageRequest

  struct GenericResponse
    Message.def_response(Nil)

    alias Result = JSON::Any
  end

  struct GenericErrorResponse
    Message.def_error_response(Nil)

    alias ErrorData = JSON::Any
  end

  # The base protocol offers support for request cancellation.
  #
  # A request that got canceled still needs to return from the server and send
  # a response back. It can not be left open / hanging. This is in line with
  # the JSON RPC protocol that requires that every request sends a response
  # back. In addition it allows for returning partial results on cancel.
  # If the requests returns an error response on cancellation it is advised
  # to set the error code to ErrorCodes.RequestCancelled.
  #
  # Notification and requests whose methods start with ‘$/’ are messages
  # which are protocol implementation dependent and might not be implementable
  # in all clients or servers. For example if the server implementation uses a
  # single threaded synchronous programming language then there is little a
  # server can do to react to a ‘$/cancelRequest’. If a server or client
  # receives notifications or requests starting with ‘$/’ it is free to
  # ignore them if they are unknown.
  struct Cancel
    Message.def_notification("$/cancelRequest")

    struct Params
      include JSON::Serializable
      property id : Int64 | String

      def initialize(@id = 0_i64); end
    end
  end

  # The initialize request is sent as the first request from the client to the
  # server. If the server receives a request or notification before the
  # initialize request it should act as follows:
  # * For a request the response should be an error with code: -32002.
  #   The message can be picked by the server.
  # * Notifications should be dropped, except for the exit notification.
  #   This will allow the exit of a server without an initialize request.
  #
  # Until the server has responded to the initialize request with an
  # InitializeResult, the client must not send any additional requests or
  # notifications to the server. In addition the server is not allowed to send
  # any requests or notifications to the client until it has responded with an
  # InitializeResult, with the exception that during the initialize request
  # the server is allowed to send the notifications window/showMessage,
  # window/logMessage and telemetry/event as well as the
  # window/showMessageRequest request to the client.
  #
  # The initialize request may only be sent once.
  struct Initialize
    Message.def_request("initialize")

    struct Params
      include JSON::Serializable

      # The process Id of the parent process that started
      # the server. Is null if the process has not been started by another process.
      # If the parent process is not alive then the server should exit (see exit notification) its process.
      @[JSON::Field(key: "processId", emit_null: true)]
      property process_id : Int64?

      # The rootPath of the workspace. Is null
      # if no folder is open.
      #
      # @deprecated in favour of rootUri.
      @[JSON::Field(key: "rootPath")]
      property _root_path : String?

      # The rootUri of the workspace. Is null if no
      # folder is open. If both `rootPath` and `rootUri` are set
      # `rootUri` wins.
      @[JSON::Field(key: "rootUri", emit_null: true, converter: LSP::JSONUtil::URIStringOrNil)]
      property root_uri : URI?

      # User provided initialization options.
      @[JSON::Field(key: "initializationOptions")]
      property options : JSON::Any?

      # The capabilities provided by the client (editor or tool)
      property capabilities : Data::ClientCapabilities

      # The initial trace setting. If omitted trace is disabled ('off').
      property trace : String = "off"

      # The workspace folders configured in the client when the server starts.
      # This property is only available if the client supports workspace folders.
      # It can be `null` if the client supports workspace folders but none are
      # configured.
      #
      # Since 3.6.0
      @[JSON::Field(key: "workspaceFolders")]
      property workspace_folders : Array(Data::WorkspaceFolder) = [] of Data::WorkspaceFolder

      def initialize(
        @process_id = nil,
        @root_uri = nil,
        @options = nil,
        @capabilities = Data::ClientCapabilities.new,
        @trace = "off",
        @workspace_folders = [] of Data::WorkspaceFolder
      )
        @_root_path = nil
      end
    end

    struct Result
      include JSON::Serializable
      property capabilities : Data::ServerCapabilities

      def initialize(@capabilities = Data::ServerCapabilities.new)
      end
    end

    struct ErrorData
      include JSON::Serializable
      # Indicates whether the client execute the following retry logic:
      # (1) show the message provided by the ResponseError to the user
      # (2) user selects retry or cancel
      # (3) if user selected retry the initialize method is sent again.
      property retry : Bool

      def initialize(@retry = true)
      end
    end
  end

  # The initialized notification is sent from the client to the server after
  # the client received the result of the initialize request but before the
  # client is sending any other request or notification to the server.
  # The server can use the initialized notification for example to dynamically
  # register capabilities. The initialized notification may only be sent once.
  struct Initialized
    Message.def_notification("initialized", false)
  end

  # The shutdown request is sent from the client to the server.
  # It asks the server to shut down, but to not exit (otherwise the response
  # might not be delivered correctly to the client). There is a separate exit
  # notification that asks the server to exit.
  struct Shutdown
    Message.def_request("shutdown", false)

    alias Result = Nil
    alias ErrorData = Nil

    def self.empty_result
      nil
    end
  end

  # A notification to ask the server to exit its process.
  # The server should exit with success code 0 if the shutdown request has
  # been received before; otherwise with error code 1.
  struct Exit
    Message.def_notification("exit", false)
  end

  # The show message notification is sent from a server to a client to ask
  # the client to display a particular message in the user interface.
  struct ShowMessage
    Message.def_notification("window/showMessage")

    struct Params
      include JSON::Serializable
      @[JSON::Field(converter: Enum::ValueConverter(LSP::Data::MessageType))]
      property type : Data::MessageType
      property message : String

      def initialize(@type = Data::MessageType::Error, @message = "")
      end
    end
  end

  # The show message request is sent from a server to a client to ask
  # the client to display a particular message in the user interface.
  # In addition to the show message notification the request allows
  # to pass actions and to wait for an answer from the client.
  struct ShowMessageRequest
    Message.def_request("window/showMessageRequest")

    struct Params
      include JSON::Serializable
      @[JSON::Field(converter: Enum::ValueConverter(LSP::Data::MessageType))]
      property type : Data::MessageType
      property message : String
      property actions : Array(LSP::Data::MessageActionItem) = [] of LSP::Data::MessageActionItem

      def initialize(
        @type = LSP::Data::MessageType::Log,
        @message = "",
        @actions = [] of LSP::Data::MessageActionItem
      )
      end
    end

    alias Result = LSP::Data::MessageActionItem?
    alias ErrorData = Nil

    def self.empty_result
      nil
    end
  end

  # The log message notification is sent from the server to the client to ask
  # the client to log a particular message.
  struct LogMessage
    Message.def_notification("window/logMessage")

    struct Params
      include JSON::Serializable
      @[JSON::Field(converter: Enum::ValueConverter(LSP::Data::MessageType))]
      property type : Data::MessageType
      property message : String

      def initialize(@type = Data::MessageType::Error, @message = "")
      end
    end
  end

  # The telemetry notification is sent from the server to the client to ask
  # the client to log a telemetry event.
  struct Telemetry
    Message.def_notification("telemetry/event")

    alias Params = JSON::Any
  end

  # The client/registerCapability request is sent from the server to the client
  # to register for a new capability on the client side. Not all clients need
  # to support dynamic capability registration. A client opts in via the
  # dynamicRegistration property on the specific client capabilities.
  # A client can even provide dynamic registration for capability A but
  # not for capability B (see TextDocumentClientCapabilities as an example).
  # TODO: struct RegisterCapability

  # The client/unregisterCapability request is sent from the server to the
  # client to unregister a previously registered capability.
  # TODO: struct UnregisterCapability

  # Many tools support more than one root folder per workspace. Examples for
  # this are VS Code’s multi-root support, Atom’s project folder support or
  # Sublime’s project support. If a client workspace consists of multiple roots
  # then a server typically needs to know about this. The protocol up to now
  # assumes one root folder which is announce to the server by the rootUri
  # property of the InitializeParams. If the client supports workspace folders
  # and announces them via the corrsponding workspaceFolders client capability
  # the InitializeParams contain an additional property workspaceFolders with
  # the configured workspace folders when the server starts.
  #
  # The workspace/workspaceFolders request is sent from the server to the
  # client to fetch the current open list of workspace folders. Returns null
  # in the response if only a single file is open in the tool. Returns an
  # empty array if a workspace is open but no folders are configured.
  # TODO: struct WorkspaceFolders

  # The workspace/didChangeWorkspaceFolders notification is sent from the
  # client to the server to inform the server about workspace folder
  # configuration changes. The notification is sent by default if both
  # ServerCapabilities/workspace/workspaceFolders and
  # ClientCapabilities/workspace/workspaceFolders are true;
  # or if the server has registered to receive this notification it first.
  #
  # To register for the workspace/didChangeWorkspaceFolders send a
  # client/registerCapability request from the client to the server.
  # The registration parameter must have a registrations item of the
  # following form, where id is a unique id used to unregister the capability
  # (the example uses a UUID):
  #     {
  #       id: "28c6150c-bd7b-11e7-abc4-cec278b6b50a",
  #       method: "workspace/didChangeWorkspaceFolders"
  #     }
  # TODO: struct DidChangeWorkspaceFolders

  # A notification sent from the client to the server to signal the change of
  # configuration settings.
  struct DidChangeConfiguration
    Message.def_notification("workspace/didChangeConfiguration")

    struct Params
      include JSON::Serializable
      property settings : JSON::Any

      def initialize(@settings = JSON::Any.new({} of String => JSON::Any))
      end
    end
  end

  # The workspace/configuration request is sent from the server to the client
  # to fetch configuration settings from the client. The request can fetch n
  # configuration settings in one roundtrip. The order of the returned
  # configuration settings correspond to the order of the passed
  # ConfigurationItems (e.g. the first item in the response is the result
  # for the first configuration item in the params).
  #
  # A ConfigurationItem consist of the configuration section to ask for and an
  # additional scope URI. The configuration section ask for is defined by the
  # server and doesn’t necessarily need to correspond to the configuration
  # store used be the client. So a server might ask for a configuration
  # cpp.formatterOptions but the client stores the configuration in a XML store
  # layout differently. It is up to the client to do the necessary conversion.
  # If a scope URI is provided the client should return the setting scoped to
  # the provided resource. If the client for example uses EditorConfig to
  # manage its settings the configuration should be returned for the passed
  # resource URI. If the client can’t provide a configuration setting for a
  # given scope then null need to be present in the returned array.
  # TODO: struct Configuration

  # The watched files notification is sent from the client to the server when
  # the client detects changes to files watched by the language client.
  # It is recommended that servers register for these file events using the
  # registration mechanism. In former implementations clients pushed file
  # events without the server actively asking for it.

  # Servers are allowed to run their own file watching mechanism and not
  # rely on clients to provide file events. However this is not recommended
  # due to the following reasons:
  #
  # * to our experience getting file watching on disk right is challenging,
  #   especially if it needs to be supported across multiple OSes.
  # * file watching is not for free especially if the implementation uses
  #   some sort of polling and keeps a file tree in memory to compare time
  #   stamps (as for example some node modules do)
  # * a client usually starts more than one server. If every server runs its
  #   own file watching it can become a CPU or memory problem.
  # * in general there are more server than client implementations.
  #   So this problem is better solved on the client side.
  # TODO: struct DidChangeWatchedFiles

  # The workspace symbol request is sent from the client to the server to list
  # project-wide symbols matching the query string.
  # TODO: struct WorkspaceSymbol

  # The workspace/executeCommand request is sent from the client to the server
  # to trigger command execution on the server.
  # In most cases the server creates a WorkspaceEdit structure and applies the
  # changes to the workspace using the request workspace/applyEdit which is
  # sent from the server to the client.
  # TODO: struct ExecuteCommand

  # The workspace/applyEdit request is sent from the server to the client to
  # modify resource on the client side.
  # TODO: struct ApplyEdit

  # The document open notification is sent from the client to the server to
  # signal newly opened text documents. The document’s truth is now managed
  # by the client and the server must not try to read the document’s truth
  # using the document’s uri.
  #
  # Open in this sense means it is managed by the client. It doesn’t
  # necessarily mean that its content is presented in an editor.
  #
  # An open notification must not be sent more than once without a
  # corresponding close notification send before. This means open and close
  # notification must be balanced and the max open count for a particular
  # textDocument is one. Note that a server’s ability to fulfill requests
  # is independent of whether a text document is open or closed.
  #
  # The DidOpenTextDocumentParams contain the language id the document is
  # associated with. If the language Id of a document changes, the client
  # needs to send a textDocument/didClose to the server followed by a
  # textDocument/didOpen with the new language id if the server handles the
  # new language id as well.
  struct DidOpen
    Message.def_notification("textDocument/didOpen")

    struct Params
      include JSON::Serializable
      # The document that was opened.
      @[JSON::Field(key: "textDocument")]
      property text_document : Data::TextDocumentItem

      def initialize(@text_document = Data::TextDocumentItem.new)
      end
    end
  end

  # The document change notification is sent from the client to the server to
  # signal changes to a text document. In 2.0 the shape of the params has
  # changed to include proper version numbers and language ids.
  struct DidChange
    Message.def_notification("textDocument/didChange")

    struct Params
      include JSON::Serializable

      # The document that did change. The version number points
      # to the version after all provided content changes have
      # been applied.
      @[JSON::Field(key: "textDocument")]
      property text_document : Data::TextDocumentVersionedIdentifier

      # The actual content changes. The content changes describe single state
      # changes to the document. So if there are two content changes
      # c1 and c2 for a document in state S then c1 move the document
      # to S' and c2 to S''.
      @[JSON::Field(key: "contentChanges")]
      property content_changes : Array(Data::TextDocumentContentChangeEvent)

      def initialize(
        @text_document = Data::TextDocumentVersionedIdentifier.new,
        @content_changes = [] of Data::TextDocumentContentChangeEvent
      )
      end
    end
  end

  # The document will save notification is sent from the client to the server
  # before the document is actually saved.
  struct WillSave
    Message.def_notification("textDocument/willSave")

    struct Params
      include JSON::Serializable

      # The document that will be saved.
      @[JSON::Field(key: "textDocument")]
      property text_document : Data::TextDocumentIdentifier

      # Represents the reason why the document will be saved.
      @[JSON::Field(converter: Enum::ValueConverter(LSP::Data::TextDocumentSaveReason))]
      property reason : Data::TextDocumentSaveReason

      def initialize(
        @text_document = Data::TextDocumentIdentifier.new,
        @reason = Data::TextDocumentSaveReason::Manual
      )
      end
    end
  end

  # The document will save request is sent from the client to the server before
  # the document is actually saved. The request can return an array of
  # TextEdits which will be applied to the text document before it is saved.
  #
  # Please note that clients might drop results if computing the text edits
  # took too long or if a server constantly fails on this request.
  # This is done to keep the save fast and reliable.
  # TODO: struct WillSaveWaitUntil

  # The document save notification is sent from the client to the server when
  # the document was saved in the client.
  struct DidSave
    Message.def_notification("textDocument/didSave")

    struct Params
      include JSON::Serializable

      # The document that was saved.
      @[JSON::Field(key: "textDocument")]
      property text_document : Data::TextDocumentIdentifier

      # Optional the content when saved. Depends on the includeText value
      # when the save notification was requested.
      property text : String?

      def initialize(
        @text_document = Data::TextDocumentIdentifier.new,
        @text = nil
      )
      end
    end
  end

  # The document close notification is sent from the client to the server when
  # the document got closed in the client. The document’s truth now exists
  # where the document’s uri points to (e.g. if the document’s uri is a file
  # uri the truth now exists on disk).
  # As with the open notification the close notification is about managing
  # the document’s content. Receiving a close notification doesn’t mean that
  # the document was open in an editor before. A close notification requires
  # a previous open notification to be sent.
  # Note that a server’s ability to fulfill requests is independent of whether
  # a text document is open or closed.
  struct DidClose
    Message.def_notification("textDocument/didClose")

    struct Params
      include JSON::Serializable

      # The document that was closed.
      @[JSON::Field(key: "textDocument")]
      property text_document : Data::TextDocumentIdentifier

      def initialize(@text_document = Data::TextDocumentIdentifier.new)
      end
    end
  end

  # Diagnostics notification are sent from the server to the client to signal
  # results of validation runs.
  #
  # Diagnostics are “owned” by the server so it is the server’s responsibility
  # to clear them if necessary. The following rule is used for VS Code servers
  # that generate diagnostics:
  #
  # * if a language is single file only (for example HTML) then diagnostics are
  #   cleared by the server when the file is closed.
  # * if a language has a project system (for example C#) diagnostics are not
  #   cleared when a file closes. When a project is opened all diagnostics for
  #   all files are recomputed (or read from a cache).
  #
  # When a file changes it is the server’s responsibility to re-compute
  # diagnostics and push them to the client. If the computed set is empty it
  # has to push the empty array to clear former diagnostics. Newly pushed
  # diagnostics always replace previously pushed diagnostics. There is no
  # merging that happens on the client side.
  struct PublishDiagnostics
    Message.def_notification("textDocument/publishDiagnostics")

    struct Params
      include JSON::Serializable

      # The URI for which diagnostic information is reported.
      @[JSON::Field(converter: LSP::JSONUtil::URIString)]
      property uri : URI

      # An array of diagnostic information items.
      property diagnostics : Array(Data::Diagnostic)

      def initialize(@uri = URI.new, @diagnostics = [] of Data::Diagnostic)
      end
    end
  end

  # The Completion request is sent from the client to the server to compute
  # completion items at a given cursor position. Completion items are
  # presented in the IntelliSense user interface. If computing full completion
  # items is expensive, servers can additionally provide a handler for the
  # completion item resolve request (‘completionItem/resolve’). This request
  # is sent when a completion item is selected in the user interface.
  # A typical use case is for example: the ‘textDocument/completion’ request
  # doesn’t fill in the documentation property for returned completion items
  # since it is expensive to compute. When the item is selected in the user
  # interface then a ‘completionItem/resolve’ request is sent with the selected
  # completion item as a param. The returned completion item should have the
  # documentation property filled in. The request can delay the computation
  # of the detail and documentation properties. However, properties that are
  # needed for the initial sorting and filtering, like sortText, filterText,
  # insertText, and textEdit must be provided in the textDocument/completion
  # request and must not be changed during resolve.
  struct Completion
    Message.def_request("textDocument/completion")

    struct Params
      include JSON::Serializable

      # The text document.
      @[JSON::Field(key: "textDocument")]
      property text_document : Data::TextDocumentIdentifier

      # The position inside the text document.
      property position : Data::Position

      # The completion context. This is only available if the client
      # specifies to send this using
      # `ClientCapabilities.textDocument.completion.contextSupport === true`
      property context : Data::CompletionContext?

      def initialize(
        @text_document = Data::TextDocumentIdentifier.new,
        @position = Data::Position.new,
        @context = nil
      )
      end
    end

    alias Result = Data::CompletionList
    alias ErrorData = Nil
  end

  # The request is sent from the client to the server to resolve additional
  # information for a given completion item.
  struct CompletionItemResolve
    Message.def_request("completionItem/resolve")

    alias Params = Data::CompletionItem
    alias Result = Data::CompletionItem
    alias ErrorData = Nil
  end

  # The hover request is sent from the client to the server to request hover
  # information at a given text document position.
  struct Hover
    Message.def_request("textDocument/hover")

    struct Params
      include JSON::Serializable

      # The text document.
      @[JSON::Field(key: "textDocument")]
      property text_document : Data::TextDocumentIdentifier

      # The position inside the text document.
      property position : Data::Position

      def initialize(
        @text_document = Data::TextDocumentIdentifier.new,
        @position = Data::Position.new
      )
      end
    end

    # TODO: allow null result when nothing to show
    struct Result
      include JSON::Serializable

      # The hover's content
      property contents : Data::MarkupContent

      # An optional range is a range inside a text document that is used
      # to visualize a hover, e.g. by changing the background color.
      property range : Data::Range?

      def initialize(
        @contents = Data::MarkupContent.new,
        @range = nil
      )
      end
    end

    alias ErrorData = Nil
  end

  # The signature help request is sent from the client to the server to request
  # signature information at a given cursor position.
  struct SignatureHelp
    Message.def_request("textDocument/signatureHelp")

    alias Params = Hover::Params

    # TODO: allow null result when nothing to show
    struct Result
      include JSON::Serializable

      # One or more signatures.
      property signatures : Array(Data::SignatureInformation)

      # The active signature. If omitted or the value lies outside the
      # range of `signatures` the value defaults to zero or is ignored if
      # `signatures.length === 0`. Whenever possible implementors should
      # make an active decision about the active signature and shouldn't
      # rely on a default value.
      # In future version of the protocol this property might become
      # mandatory to better express this.
      @[JSON::Field(key: "activeSignature")]
      property active_signature : Int64 = 0_i64

      # The active parameter of the active signature. If omitted or the value
      # lies outside the range of `signatures[activeSignature].parameters`
      # defaults to 0 if the active signature has parameters. If
      # the active signature has no parameters it is ignored.
      # In future version of the protocol this property might become
      # mandatory to better express the active parameter if the
      # active signature does have any.
      @[JSON::Field(key: "activeParameter")]
      property active_parameter : Int64 = 0_i64

      def initialize(
        @signatures = [] of Data::SignatureInformation,
        @active_signature = 0_i64,
        @active_parameter = 0_i64
      )
      end
    end

    alias ErrorData = Nil
  end

  # The goto definition request is sent from the client to the server to
  # resolve the definition location of a symbol at a given text document
  # position.
  # TODO: struct Definition

  # The goto type definition request is sent from the client to the server to
  # resolve the type definition location of a symbol at a given text document
  # position.
  # TODO: struct TypeDefinition

  # The goto implementation request is sent from the client to the server to
  # resolve the implementation location of a symbol at a given text document
  # position.
  # TODO: struct Implementation

  # The references request is sent from the client to the server to resolve
  # project-wide references for the symbol denoted by the given text document
  # position.
  # TODO: struct References

  # The document highlight request is sent from the client to the server to
  # resolve a document highlights for a given text document position.
  # For programming languages this usually highlights all references to the
  # symbol scoped to this file. However we kept ‘textDocument/documentHighlight’
  # and ‘textDocument/references’ separate requests since the first one is
  # allowed to be more fuzzy.
  #
  # Symbol matches usually have a DocumentHighlightKind of Read or Write
  # whereas fuzzy or textual matches use Text as the kind.
  # TODO: struct DocumentHighlight

  # The document symbol request is sent from the client to the server to
  # return a flat list of all symbols found in a given text document.
  # Neither the symbol’s location range nor the symbol’s container name should
  # be used to infer a hierarchy.
  # TODO: struct DocumentSymbol

  # The code action request is sent from the client to the server to compute
  # commands for a given text document and range. These commands are typically
  # code fixes to either fix problems or to beautify/refactor code.
  #
  # The result of a textDocument/codeAction request is an array of Command
  # literals which are typically presented in the user interface. When the
  # command is selected the server should be contacted again (via the
  # workspace/executeCommand) request to execute the command.
  #
  # Since version 3.8.0: support for CodeAction literals to enable the
  # following scenarios:
  #
  # * the ability to directly return a workspace edit from the code action
  #   request. This avoids having another server roundtrip to execute an actual
  #   code action. However server providers should be aware that if the code
  #   action is expensive to compute or the edits are huge it might still be
  #   beneficial if the result is simply a command and the actual edit is only
  #   computed when needed.
  # * the ability to group code actions using a kind. Clients are allowed to
  #   ignore that information. However it allows them to better group code
  #   action for example into corresponding menus (e.g. all refactor code
  #   actions into a refactor menu).
  #
  # Clients need to announce their support for code action literals and code
  # action kinds via the corresponding client capability
  # textDocument.codeAction.codeActionLiteralSupport.
  # TODO: struct CodeAction

  # The code lens request is sent from the client to the server to compute
  # code lenses for a given text document.
  # TODO: struct CodeLens

  # The code lens resolve request is sent from the client to the server to
  # resolve the command for a given code lens item.
  # TODO: struct CodeLensResolve

  # The document links request is sent from the client to the server to request
  # the location of links in a document.
  # TODO: struct DocumentLink

  # The document link resolve request is sent from the client to the server to
  # resolve the target of a given document link.
  # TODO: struct DocumentLinkResolve

  # The document color request is sent from the client to the server to list
  # all color references found in a given text document. Along with the range,
  # a color value in RGB is returned.
  #
  # Clients can use the result to decorate color references in an editor.
  # For example:
  # * Color boxes showing the actual color next to the reference
  # * Show a color picker when a color reference is edited
  # TODO: struct DocumentColor

  # The color presentation request is sent from the client to the server to
  # obtain a list of presentations for a color value at a given location.
  # Clients can use the result to:
  # * modify a color reference.
  # * show in a color picker and let users pick one of the presentations
  # TODO: struct ColorPresentation

  # The document formatting request is sent from the client to the server to
  # format a whole document.
  struct Formatting
    Message.def_request("textDocument/formatting")

    struct Params
      include JSON::Serializable

      # The document to format.
      @[JSON::Field(key: "textDocument")]
      property text_document : Data::TextDocumentIdentifier

      # The format options.
      property options : Data::FormattingOptions

      def initialize(
        @text_document = Data::TextDocumentIdentifier.new,
        @options = Data::FormattingOptions.new
      )
      end
    end

    alias Result = Array(Data::TextEdit)

    alias ErrorData = Nil
  end

  # The document range formatting request is sent from the client to the server
  # to format a given range in a document.
  struct RangeFormatting
    Message.def_request("textDocument/rangeFormatting")

    struct Params
      include JSON::Serializable

      # The document to format.
      @[JSON::Field(key: "textDocument")]
      property text_document : Data::TextDocumentIdentifier

      # The range to format.
      property range : Data::Range

      # The format options.
      property options : Data::FormattingOptions

      def initialize(
        @text_document = Data::TextDocumentIdentifier.new,
        @range = Data::Range.new,
        @options = Data::FormattingOptions.new
      )
      end
    end

    alias Result = Array(Data::TextEdit)

    alias ErrorData = Nil
  end

  # The document on type formatting request is sent from the client to the
  # server to format parts of the document during typing.
  struct OnTypeFormatting
    Message.def_request("textDocument/onTypeFormatting")

    struct Params
      include JSON::Serializable

      # The text document.
      @[JSON::Field(key: "textDocument")]
      property text_document : Data::TextDocumentIdentifier

      # The position inside the text document.
      property position : Data::Position

      # The character that has been typed.
      property ch : String

      # The format options.
      property options : Data::FormattingOptions

      def initialize(
        @text_document = Data::TextDocumentIdentifier.new,
        @position = Data::Position.new,
        @ch = "",
        @options = Data::FormattingOptions.new
      )
      end
    end

    alias Result = Array(Data::TextEdit)

    alias ErrorData = Nil
  end

  # The rename request is sent from the client to the server to perform a
  # workspace-wide rename of a symbol.
  # TODO: struct Rename

  # The prepare rename request is sent from the client to the server to setup
  # and test the validity of a rename operation at a given location.
  # TODO: struct PrepareRename

  # The folding range request is sent from the client to the server to return
  # all folding ranges found in a given text document.
  # TODO: struct FoldingRange
end
