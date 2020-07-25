require "../spec_helper"

class SpecCommand < Clim
  main do
    desc "main command."
    usage "main [sub_command] [arguments]"
    option "-g WORDS", "--greeting=WORDS", type: String, desc: "Words of greetings.", default: "Hello"
    option "-n NAME", type: Array(String), desc: "Target name.", default: ["Taro"], required: true
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

class SpecCommandNoSubCommands < Clim
  main do
    desc "main command."
    usage "main [sub_command] [arguments]"
    option "-g WORDS", "--greeting=WORDS", type: String, desc: "Words of greetings.", default: "Hello"
    option "-n NAME", type: Array(String), desc: "Target name.", default: ["Taro"], required: true
    run do |opts, args|
    end
  end
end

describe Clim::Command do
  describe "#help_template" do
    it "returns help string with sub commands." do
      SpecCommand.command.help_template_str.should eq <<-OPTIONS

        main command.

        Usage:

          main [sub_command] [arguments]

        Options:

          -g WORDS, --greeting=WORDS       Words of greetings. [type:String] [default:"Hello"]
          -n NAME                          Target name. [type:Array(String)] [default:["Taro"]] [required]
          --help                           Show this help.

        Sub Commands:

          abc, def, ghi            abc command.
          abcdef, ghijkl, mnopqr   abcdef command.


      OPTIONS
    end
    it "returns help string without sub commands." do
      SpecCommandNoSubCommands.command.help_template_str.should eq <<-OPTIONS

        main command.

        Usage:

          main [sub_command] [arguments]

        Options:

          -g WORDS, --greeting=WORDS       Words of greetings. [type:String] [default:"Hello"]
          -n NAME                          Target name. [type:Array(String)] [default:["Taro"]] [required]
          --help                           Show this help.


      OPTIONS
    end
  end
  describe "#desc" do
    it "returns desc." do
      SpecCommand.command.desc.should eq "main command."
    end
  end
  describe "#usage" do
    it "returns usage." do
      SpecCommand.command.usage.should eq "main [sub_command] [arguments]"
    end
  end
  describe "#names" do
    it "returns name and alias_name of sub commands." do
      SpecCommand.command.@sub_commands.to_a[0].names.should eq ["abc", "def", "ghi"]
      SpecCommand.command.@sub_commands.to_a[1].names.should eq ["abcdef", "ghijkl", "mnopqr"]
    end
  end
end
