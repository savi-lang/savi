require "json"

module LSP::Data
  struct WorkspaceFolder
    include JSON::Serializable

    # The associated URI for this workspace folder.
    @[JSON::Field(converter: LSP::JSONUtil::URIString)]
    property uri : URI

    # The name of the workspace folder. Defaults to the
    # uri's basename.
    property name : String

    def initialize
      @uri = URI.new
      @name = ""
    end
  end
end
