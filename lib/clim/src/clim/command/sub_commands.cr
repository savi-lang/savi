require "./options/*"
require "../exception"
require "option_parser"

class Clim
  abstract class Command
    class SubCommands
      @sub_commands : Array(Command)

      def initialize(@sub_commands : Array(Command) = [] of Command)
      end

      def <<(command : Command)
        @sub_commands << command
      end

      def to_a
        @sub_commands
      end

      def help_info
        @sub_commands.map do |cmd|
          {
            names:     cmd.names,
            desc:      cmd.desc,
            help_line: help_line_of(cmd),
          }
        end
      end

      private def help_line_of(cmd)
        names_and_spaces = cmd.names.join(", ") +
                           "#{" " * (max_name_length - cmd.names.join(", ").size)}"
        "    #{names_and_spaces}   #{cmd.desc}"
      end

      private def max_name_length
        @sub_commands.empty? ? 0 : @sub_commands.map(&.names.join(", ").size).max
      end

      def find_by_name(name) : Array(Command)
        @sub_commands.select do |cmd|
          cmd.name == name || cmd.alias_name.includes?(name)
        end
      end
    end
  end
end
