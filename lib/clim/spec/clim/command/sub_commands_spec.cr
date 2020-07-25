require "../../spec_helper"
require "../../../src/clim/command"

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

describe Clim::Command::SubCommands do
  describe "#help_info" do
    it "returns sub commands help info." do
      SpecCommand.command.@sub_commands.help_info.should eq [
        {
          names:     ["abc", "def", "ghi"],
          desc:      "abc command.",
          help_line: "    abc, def, ghi            abc command.",
        },
        {
          names:     ["abcdef", "ghijkl", "mnopqr"],
          desc:      "abcdef command.",
          help_line: "    abcdef, ghijkl, mnopqr   abcdef command.",
        },
      ]
    end
    it "returns sub commands info without sub commands." do
      SpecCommandNoSubCommands.command.@sub_commands.help_info.should eq [] of Array(NamedTuple(names: Array(String), desc: String, help_line: String))
    end
  end
  describe "#find_by_name" do
    it "returns found sub command." do
      actual = SpecCommand.command.@sub_commands.find_by_name("ghijkl")
      actual.size.should eq 1
      actual.first.name.should eq "abcdef"
      actual.first.desc.should eq "abcdef command."
      actual.first.usage.should eq "main abcdef [options] [files]"
      actual.first.alias_name.should eq ["ghijkl", "mnopqr"]
    end
    it "returns sub commands info without sub commands." do
      SpecCommandNoSubCommands.command.@sub_commands.find_by_name("ghijkl").should eq [] of Clim::Command
    end
  end
end
