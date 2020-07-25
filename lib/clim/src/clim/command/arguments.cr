require "./arguments/*"

class Clim
  abstract class Command
    class Arguments
      getter help_string : String = ""
      getter all_args : Array(String) = [] of String
      getter unknown_args : Array(String) = [] of String
      getter argv : Array(String) = [] of String

      def set_values_by_input_argument(unknown_args : Array(String))
        @all_args = unknown_args.dup

        args_array = to_a
        defined_args_size = args_array.size
        unknown_args_size = unknown_args.size

        defined_args_values = unknown_args.shift(defined_args_size)
        defined_args_values.each_with_index do |value, i|
          args_array[i].set_value(value)
        end

        @unknown_args = unknown_args
      end

      def set_argv(@argv : Array(String))
      end

      def required_validate!(options : Options)
        if options.responds_to?(:help)
          return if options.help
        end
        return if invalid_required_names.empty?
        raise ClimInvalidOptionException.new "Required arguments. \"#{invalid_required_names.join("\", \"")}\""
      end

      def invalid_required_names
        ret = [] of String | Nil
        {% for iv in @type.instance_vars.reject { |iv| ["help_string", "all_args", "unknown_args", "argv"].includes?(iv.stringify) } %}
          name_or_nil = {{iv}}.required_not_set? ? {{iv}}.display_name : nil
          ret << name_or_nil
        {% end %}
        ret.compact
      end

      def help_info
        tmp_array = to_a.map(&.display_name.size)
        max_name_size = tmp_array.empty? ? nil : tmp_array.max
        to_a.map_with_index do |argument|
          found_info = info.find do |info_element|
            !!argument.display_name.match(/\A#{info_element[:display_name]}\z/)
          end
          next nil if found_info.nil?
          next nil if max_name_size.nil?
          found_info.merge({help_line: "    %02d. %-#{max_name_size}s      %s" % [found_info[:sequence_number], found_info[:display_name].to_s, argument.desc]})
        end.compact
      end

      def info
        {% begin %}
          {% support_types = SUPPORTED_TYPES_OF_ARGUMENT.map { |k, _| k } + [Nil] %}
          array = [] of NamedTuple(
            method_name: String,
            display_name: String,
            type: {{ support_types.map(&.stringify.+(".class")).join(" | ").id }},
            desc: String,
            default: {{ support_types.join(" | ").id }},
            required: Bool,
            sequence_number: Int32
          )
          {% for iv, index in @type.instance_vars.reject { |iv| ["help_string", "all_args", "unknown_args", "argv"].includes?(iv.stringify) } %}
            array << {{iv}}.to_named_tuple.merge({sequence_number: {{index}} + 1 })
          {% end %}
        {% end %}
      end

      def to_a
        {% begin %}
          {% support_types = SUPPORTED_TYPES_OF_ARGUMENT.map { |k, _| k } + [Nil] %}
          array = [] of Argument
          {% for iv in @type.instance_vars.reject { |iv| ["help_string", "all_args", "unknown_args", "argv"].includes?(iv.stringify) } %}
            array << {{iv}}
          {% end %}
        {% end %}
      end

      macro define_arguments(name, type, desc, default, required)
        {% method_name = name.id.stringify.gsub(/\=/, " ").split(" ").first.id.stringify.gsub(/^-+/, "").gsub(/-/, "_").id %}
        {% display_name = name.id %}
        class ArgumentsForEachCommand

          \{% if @type.constants.map(&.id.stringify).includes?("Argument_" + {{method_name.stringify}}.id.stringify) %}
            \{% raise "Argument \"" + {{method_name.stringify}}.id.stringify + "\" is already defined." %}
          \{% end %}

          class Argument_{{method_name}} < Argument
            Argument.define_argument({{method_name}}, {{type}}, {{default}}, {{required}})
          end

          {% if default == nil %}
            {% default_value = SUPPORTED_TYPES_OF_ARGUMENT[type][:nilable] ? default : SUPPORTED_TYPES_OF_ARGUMENT[type][:default] %}
          {% else %}
            {% default_value = default %}
          {% end %}

          getter {{ method_name }}_instance : Argument_{{method_name}} = Argument_{{method_name}}.new({{ method_name.stringify }}, {{ display_name.stringify }}, {{ desc }}, {{ default_value }}, {{ required }})
          def {{ method_name }}
            {{ method_name }}_instance.@value
          end
        end

      end
    end
  end
end
