require "json"

module LSP::Data
  # Represents a reference to a command. Provides a title which will be used
  # to represent a command in the UI. Commands are identified by a string
  # identifier.
  # The protocol currently doesn't specify a set of well-known commands.
  # So executing a command requires some tool extension code.
  struct Command
    JSON.mapping({
      # Title of the command, like `save`.
      title: String,

      # The identifier of the actual command handler.
      command: String,

      # Arguments that the command handler should be invoked with.
      arguments: {type: Array(JSON::Any), default: [] of JSON::Any},
    })
    def initialize(
      @title = "",
      @command = "",
      @arguments = [] of JSON::Any)
    end
  end
end
