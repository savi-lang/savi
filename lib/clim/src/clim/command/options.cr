require "./options/*"
require "../exception"
require "option_parser"

class Clim
  abstract class Command
    class Options
      getter help_string : String = ""

      @option_parser : OptionParser
      @unknown_args : Array(String)

      def initialize
        @unknown_args = [] of String

        @option_parser = OptionParser.new
        @option_parser.invalid_option { |opt_name| raise ClimInvalidOptionException.new "Undefined option. \"#{opt_name}\"" }
        @option_parser.missing_option { |opt_name| raise ClimInvalidOptionException.new "Option that requires an argument. \"#{opt_name}\"" }
        @option_parser.unknown_args { |ua| @unknown_args = ua }

        # options
        to_a.reject { |o| ["help", "version"].includes?(o.method_name) }.each do |option|
          on(option)
        end

        # help
        option_help = to_a.find { |o| ["help"].includes?(o.method_name) }
        raise ClimException.new("Help option setting is required.") if option_help.nil?
        on(option_help)

        # version
        option_version = to_a.find { |o| ["version"].includes?(o.method_name) }
        return nil if option_version.nil?
        on(option_version)
      end

      private def on(option)
        long = option.long
        if long.nil?
          @option_parser.on(option.short, option.desc) { |arg| option.set_value(arg) }
        else
          @option_parser.on(option.short, long, option.desc) { |arg| option.set_value(arg) }
        end
      end

      def unknown_args
        @unknown_args.dup
      end

      def set_help_string(str : String)
        @help_string = str
      end

      def parse(argv : Array(String))
        @option_parser.parse(argv.dup)
      end

      def required_validate!
        opts = self.dup
        if opts.responds_to?(:help)
          return if opts.help
        end
        return if invalid_required_names.empty?
        raise ClimInvalidOptionException.new "Required options. \"#{invalid_required_names.join("\", \"")}\""
      end

      private def invalid_required_names
        ret = [] of String | Nil
        {% for iv in @type.instance_vars.reject { |iv| ["help_string", "option_parser", "unknown_args"].includes?(iv.stringify) } %}
          short_or_nil = {{iv}}.required_not_set? ? {{iv}}.short : nil
          ret << short_or_nil
        {% end %}
        ret.compact
      end

      def help_info
        @option_parser.@flags.map do |flag|
          found_info = info.find do |info_element|
            !!flag.match(/\A\s+?#{info_element[:names].join(", ")}/)
          end
          next nil if found_info.nil?
          found_info.merge({help_line: flag})
        end.compact
      end

      def info
        {% begin %}
          {% support_types = SUPPORTED_TYPES_OF_OPTION.map { |k, _| k } + [Nil] %}
          array = [] of NamedTuple(names: Array(String), type: {{ support_types.map(&.stringify.+(".class")).join(" | ").id }}, desc: String, default: {{ support_types.join(" | ").id }}, required: Bool)
          {% for iv in @type.instance_vars.reject { |iv| ["help_string", "option_parser", "unknown_args"].includes?(iv.stringify) } %}
            array << {{iv}}.to_named_tuple
          {% end %}
        {% end %}
      end

      def to_a
        {% begin %}
          {% support_types = SUPPORTED_TYPES_OF_OPTION.map { |k, _| k } + [Nil] %}
          array = [] of Option
          {% for iv in @type.instance_vars.reject { |iv| ["help_string", "option_parser", "unknown_args"].includes?(iv.stringify) } %}
            array << {{iv}}
          {% end %}
        {% end %}
      end

      macro define_options(short, long, type, desc, default, required)
        {% base_option_name = long == nil ? short : long %}
        {% option_name = base_option_name.id.stringify.gsub(/\=/, " ").split(" ").first.id.stringify.gsub(/^-+/, "").gsub(/-/, "_").id %}
        class OptionsForEachCommand
          class Option_{{option_name}} < Option
            Option.define_option({{option_name}}, {{type}}, {{default}}, {{required}})
          end

          {% default = false if type.id.stringify == "Bool" && default == nil %}
          {% raise "You can not specify 'required: true' for Bool option." if type.id.stringify == "Bool" && required == true %}

          {% if default == nil %}
            {% default_value = SUPPORTED_TYPES_OF_OPTION[type][:nilable] ? default : SUPPORTED_TYPES_OF_OPTION[type][:default] %}
          {% else %}
            {% default_value = default %}
          {% end %}

          getter {{ option_name }}_instance : Option_{{option_name}} = Option_{{option_name}}.new({{ short }}, {% unless long == nil %} {{ long }}, {% end %} {{ desc }}, {{ default_value }}, {{ required }})
          def {{ option_name }}
            {{ option_name }}_instance.@value
          end
        end
      end
    end
  end
end
