require "./../../spec_helper"

class SpecCommand < Clim
  main do
    desc "main command."
    usage "main [sub_command] [arguments]"
    option "-g WORDS", "--greeting=WORDS", type: String, desc: "Words of greetings.", default: "Hello"
    option "-n NAME", type: Array(String), desc: "Target name.", default: ["Taro"], required: true
    argument "argument1", type: String, desc: "first argument.", default: "default value", required: true
    argument "argument2foo", type: Int32, desc: "second argument.", default: 1, required: false
    argument "kebab-case-name", type: Int32, desc: "kebab-case-name argument.", default: 1, required: false
    argument "snake_case_name", type: Int32, desc: "snake_case_name argument.", default: 1, required: false
    argument "camelCaseName", type: Int32, desc: "camelCaseName argument.", default: 1, required: false
    run do |opts, args|
    end
    sub "abc" do
      desc "abc command."
      usage "main abc [tool] [arguments]"
      alias_name "def", "ghi"
      run do |opts, args|
      end
    end
    sub "abcdef" do
      desc "abcdef command."
      usage "main abcdef [options] [files]"
      alias_name "ghijkl", "mnopqr"
      run do |opts, args|
      end
    end
  end
end

class SpecCommandNoOptions < Clim
  main do
    desc "main command."
    usage "main [sub_command] [arguments]"
    argument "argument3", type: String, desc: "third argument.", default: "default value", required: true
    run do |opts, args|
    end
  end
end

describe Clim::Command::Arguments do
  describe "#help_info" do
    it "returns arguments help info." do
      SpecCommand.command.@arguments.help_info.should eq [
        {
          method_name:     "argument1",
          display_name:    "argument1",
          type:            String,
          desc:            "first argument.",
          default:         "default value",
          required:        true,
          sequence_number: 1,
          help_line:       "    01. argument1            first argument. [type:String] [default:\"default value\"] [required]",
        },
        {
          method_name:     "argument2foo",
          display_name:    "argument2foo",
          type:            Int32,
          desc:            "second argument.",
          default:         1,
          required:        false,
          sequence_number: 2,
          help_line:       "    02. argument2foo         second argument. [type:Int32] [default:1]",
        },
        {
          method_name:     "kebab_case_name",
          display_name:    "kebab-case-name",
          type:            Int32,
          desc:            "kebab-case-name argument.",
          default:         1,
          required:        false,
          sequence_number: 3,
          help_line:       "    03. kebab-case-name      kebab-case-name argument. [type:Int32] [default:1]",
        },
        {
          method_name:     "snake_case_name",
          display_name:    "snake_case_name",
          type:            Int32,
          desc:            "snake_case_name argument.",
          default:         1,
          required:        false,
          sequence_number: 4,
          help_line:       "    04. snake_case_name      snake_case_name argument. [type:Int32] [default:1]",
        },
        {
          method_name:     "camelCaseName",
          display_name:    "camelCaseName",
          type:            Int32,
          desc:            "camelCaseName argument.",
          default:         1,
          required:        false,
          sequence_number: 5,
          help_line:       "    05. camelCaseName        camelCaseName argument. [type:Int32] [default:1]",
        },
      ]
    end
    it "returns arguments help info without sub commands." do
      SpecCommandNoOptions.command.@arguments.help_info.should eq [
        {
          method_name:     "argument3",
          display_name:    "argument3",
          type:            String,
          desc:            "third argument.",
          default:         "default value",
          required:        true,
          sequence_number: 1,
          help_line:       "    01. argument3      third argument. [type:String] [default:\"default value\"] [required]",
        },
      ]
    end
  end
end
