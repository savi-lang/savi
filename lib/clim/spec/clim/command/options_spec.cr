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

describe Clim::Command::Options do
  describe "#help_info" do
    it "returns options help info." do
      SpecCommand.command.@options.help_info.should eq [
        {
          names:     ["-g WORDS", "--greeting=WORDS"],
          type:      String,
          desc:      "Words of greetings.",
          default:   "Hello",
          required:  false,
          help_line: "    -g WORDS, --greeting=WORDS       Words of greetings. [type:String] [default:\"Hello\"]",
        },
        {
          names:     ["-n NAME"],
          type:      Array(String),
          desc:      "Target name.",
          default:   ["Taro"],
          required:  true,
          help_line: "    -n NAME                          Target name. [type:Array(String)] [default:[\"Taro\"]] [required]",
        },
        {
          names:     ["--help"],
          type:      Bool,
          desc:      "Show this help.",
          default:   false,
          required:  false,
          help_line: "    --help                           Show this help.",
        },
      ]
    end
    it "returns options help info without sub commands." do
      SpecCommandNoOptions.command.@options.help_info.should eq [
        {
          names:     ["--help"],
          type:      Bool,
          desc:      "Show this help.",
          default:   false,
          required:  false,
          help_line: "    --help                           Show this help.",
        },
      ]
    end
  end
end
