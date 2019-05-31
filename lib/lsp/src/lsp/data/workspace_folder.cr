require "json"

module LSP::Data
  struct WorkspaceFolder
    JSON.mapping({
      # The associated URI for this workspace folder.
      uri: {type: URI, converter: JSONUtil::URIString},

      # The name of the workspace folder. Defaults to the
      # uri's basename.
      name: String,
    })
    def initialize
      @uri = URI.new
      @name = ""
    end
  end
end
