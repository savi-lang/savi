class Clim
  abstract class Command
    class Options
      abstract class Option
        getter short : String = ""
        getter long : String? = ""
        getter desc : String = ""
        getter required : Bool = false
        getter array_set_flag : Bool = false

        def to_named_tuple
          long_name = long
          {
            names:    long_name.nil? ? [short] : [short, long_name],
            type:     default.class,
            desc:     @desc,
            default:  default,
            required: required,
          }
        end

        def required_not_set? : Bool
          @required && !set_value?
        end

        abstract def method_name

        private def display_default
          default_value = @default.dup
          {% begin %}
            {% support_types_number = SUPPORTED_TYPES_OF_OPTION.map { |k, v| v[:type] == "number" ? k : nil }.reject(&.==(nil)) %}
            {% support_types_string = SUPPORTED_TYPES_OF_OPTION.map { |k, v| v[:type] == "string" ? k : nil }.reject(&.==(nil)) %}
            {% support_types_bool = SUPPORTED_TYPES_OF_OPTION.map { |k, v| v[:type] == "bool" ? k : nil }.reject(&.==(nil)) %}
            {% support_types_array = SUPPORTED_TYPES_OF_OPTION.map { |k, v| v[:type] == "array" ? k : nil }.reject(&.==(nil)) %}
            case default_value
            when Nil
              "nil"
            when {{*support_types_bool}}
              default_value
            when {{*support_types_string}}
              default_value.empty? ? "\"\"" : "\"#{default_value}\""
            when {{*support_types_number}}
              default_value
            {% for type in support_types_array %}
            when {{type}}
              default_value.empty? ? "[] of {{type.type_vars.first}}" : default
            {% end %}
            else
              raise ClimException.new "[#{typeof(default)}] is not supported."
            end
          {% end %}
        end

        macro define_option(option_name, type, default, required)
          {% if default != nil %}
            {% value_type = type.stringify.id %}
            {% value_default = default %}
            {% value_assign = "default".id %}
            {% default_type = type.stringify.id %}
          {% elsif default == nil && required == true %}
            {% value_type = type.stringify.id %}
            {% value_default = SUPPORTED_TYPES_OF_OPTION[type][:default] %}
            {% value_assign = SUPPORTED_TYPES_OF_OPTION[type][:default] %}
            {% default_type = SUPPORTED_TYPES_OF_OPTION[type][:nilable] ? (type.stringify + "?").id : type.stringify.id %}
          {% elsif default == nil && required == false %}
            {% value_type = SUPPORTED_TYPES_OF_OPTION[type][:nilable] ? (type.stringify + "?").id : type.stringify.id %}
            {% value_default = SUPPORTED_TYPES_OF_OPTION[type][:nilable] ? default : SUPPORTED_TYPES_OF_OPTION[type][:default] %}
            {% value_assign = SUPPORTED_TYPES_OF_OPTION[type][:nilable] ? "default".id : SUPPORTED_TYPES_OF_OPTION[type][:default] %}
            {% default_type = SUPPORTED_TYPES_OF_OPTION[type][:nilable] ? (type.stringify + "?").id : type.stringify.id %}
          {% end %}

          getter method_name : String = {{option_name.stringify}}
          getter value : {{value_type}} = {{value_default}}
          getter default : {{default_type}} = {{ SUPPORTED_TYPES_OF_OPTION[type][:nilable] ? default : SUPPORTED_TYPES_OF_OPTION[type][:default] }}
          getter set_value : Bool = false

          def initialize(@short : String, @long : String, @desc : String, @default : {{default_type}}, @required : Bool)
            @value = {{value_assign}}
          end

          def initialize(@short : String, @desc : String, @default : {{default_type}}, @required : Bool)
            @long = nil
            @value = {{value_assign}}
          end

          def desc
            desc = @desc
            return desc if ["help", "version"].includes?({{option_name.stringify}})
            desc = desc + " [type:#{{{type}}.to_s}]"
            desc = desc + " [default:#{display_default}]" unless {{(default == nil).id}}
            desc = desc + " [required]" if required
            desc
          end

          def set_value(arg : String)
            {% raise "Type [#{type}] is not supported on option." unless SUPPORTED_TYPES_OF_OPTION.keys.includes?(type) %}
            @value = {{SUPPORTED_TYPES_OF_OPTION[type][:convert_arg_process].id}}
            @set_value = true
          rescue ex
            raise ClimInvalidTypeCastException.new ex.message
          end

          def set_value?
            @set_value
          end
        end

        macro add_array_value(type, casted_arg)
          @value = [] of {{type}} if @array_set_flag == false
          @array_set_flag = true
          @value.nil? ? [{{casted_arg}}] : @value.try &.<<({{casted_arg}})
        end
      end
    end
  end
end
