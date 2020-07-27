require "./../../spec_helper"

describe "README.md spec, " do
  it "./minimum foo bar baz" do
    `crystal run spec/clim/readme/files/minimum.cr --no-color -- foo bar baz`.should eq <<-DISPLAY
    foo, bar, baz!

    DISPLAY
  end
  it "./hello --help" do
    `crystal run spec/clim/readme/files/hello.cr --no-color -- --help`.should eq <<-DISPLAY

      Hello CLI tool.

      Usage:

        hello [options] [arguments] ...

      Options:

        -g WORDS, --greeting=WORDS       Words of greetings. [type:String] [default:"Hello"]
        --help                           Show this help.
        --version                        Show version.

      Arguments:

        01. first_member       first member name. [type:String] [default:"member1"]
        02. second_member      second member name. [type:String] [default:"member2"]


    DISPLAY
  end
  it "./hello -g 'Good night' Ichiro Miko Takashi Taro" do
    `crystal run spec/clim/readme/files/hello.cr --no-color -- -g 'Good night' Ichiro Miko Takashi Taro`.should eq <<-DISPLAY
    Good night, Ichiro & Miko !
    And Takashi, Taro !

    DISPLAY
  end
  it "./fcrystal" do
    `crystal run spec/clim/readme/files/fake-crystal-command.cr --no-color --`.should eq <<-DISPLAY

      Fake Crystal command.

      Usage:

        fcrystal [sub_command] [arguments]

      Options:

        --help                           Show this help.

      Sub Commands:

        tool   run a tool
        spec   build and run specs


    DISPLAY
  end
  it "./fcrystal tool --help" do
    `crystal run spec/clim/readme/files/fake-crystal-command.cr --no-color -- tool --help`.should eq <<-DISPLAY

      run a tool

      Usage:

        fcrystal tool [tool] [arguments]

      Options:

        --help                           Show this help.

      Sub Commands:

        format   format project, directories and/or files


    DISPLAY
  end
  it "./fcrystal tool format" do
    `crystal run spec/clim/readme/files/fake-crystal-command.cr --no-color -- tool format`.should eq <<-DISPLAY
    Fake Crystal tool format!!

    DISPLAY
  end
  it "(alias_name) ./mycli sub" do
    `crystal run spec/clim/readme/files/alias_name.cr --no-color -- sub`.should eq <<-DISPLAY
    sub_command run!!

    DISPLAY
  end
  it "(alias_name) ./mycli alias1" do
    `crystal run spec/clim/readme/files/alias_name.cr --no-color -- alias1`.should eq <<-DISPLAY
    sub_command run!!

    DISPLAY
  end
  it "(alias_name) ./mycli alias2" do
    `crystal run spec/clim/readme/files/alias_name.cr --no-color -- alias2`.should eq <<-DISPLAY
    sub_command run!!

    DISPLAY
  end
  it "(version) ./mycli --version" do
    `crystal run spec/clim/readme/files/version.cr --no-color -- --version`.should eq <<-DISPLAY
    mycli version: 1.0.1

    DISPLAY
  end
  it "(version-short) ./mycli --version" do
    `crystal run spec/clim/readme/files/version_short.cr --no-color -- --version`.should eq <<-DISPLAY
    mycli version: 1.0.1

    DISPLAY
  end
  it "(version-short) ./mycli -v" do
    `crystal run spec/clim/readme/files/version_short.cr --no-color -- -v`.should eq <<-DISPLAY
    mycli version: 1.0.1

    DISPLAY
  end
  it "(help-short) ./mycli -h" do
    `crystal run spec/clim/readme/files/help_short.cr --no-color -- -h`.should eq <<-DISPLAY

      help directive test.

      Usage:

        mycli [options] [arguments]

      Options:

        -h, --help                       Show this help.


    DISPLAY
  end
  it "(help-short) ./mycli --help" do
    `crystal run spec/clim/readme/files/help_short.cr --no-color -- --help`.should eq <<-DISPLAY

      help directive test.

      Usage:

        mycli [options] [arguments]

      Options:

        -h, --help                       Show this help.


    DISPLAY
  end
  it "(argument) crystal run src/argument.cr -- --help" do
    `crystal run spec/clim/readme/files/argument.cr --no-color -- --help`.should eq <<-DISPLAY

      argument sample

      Usage:

        command [options] [arguments]

      Options:

        --dummy=WORDS                    dummy option [type:String]
        --help                           Show this help.

      Arguments:

        01. first-arg       first argument! [type:String] [default:"default value"]
        02. second-arg      second argument! [type:Int32] [default:999]


    DISPLAY
  end
  it "(argument) crystal run src/argument.cr -- 000 111 --dummy dummy_words 222 333" do
    `crystal run spec/clim/readme/files/argument.cr --no-color -- 000 111 --dummy dummy_words 222 333`.should eq <<-DISPLAY
    typeof(args.first_arg)    => String
           args.first_arg     => 000
    typeof(args.second_arg)   => Int32
           args.second_arg    => 111
    typeof(args.all_args)     => Array(String)
           args.all_args      => ["000", "111", "222", "333"]
    typeof(args.unknown_args) => Array(String)
           args.unknown_args  => ["222", "333"]
    typeof(args.argv)         => Array(String)
           args.argv          => ["000", "111", "--dummy", "dummy_words", "222", "333"]

    DISPLAY
  end
  it "(help_template) crystal run src/help_template_test.cr -- --help" do
    `crystal run spec/clim/readme/files/help_template.cr --no-color -- --help`.should eq <<-DISPLAY
    usage: my_cli [--version] [--help] [-P PORT|--port=PORT]
                  [-h HOST|--host=HOST] [-p PASSWORD|--password=PASSWORD] [arguments]

    Your original command line interface tool.

    options:
    -P PORT, --port=PORT
        Port number.
    -h HOST, --host=HOST
        Host name.
    -p PASSWORD, --password=PASSWORD
        Password.
    --help
        Show this help.
    --version
        Show version.

    arguments:
    01: image_name
          The name of your favorite docker image.
    02: container_id
          The ID of the running container.

    sub commands:
        sub_command   my_cli's sub_comand.

    DISPLAY
  end
  it "(io_in_run_block) crystal run src/io_in_run_block.cr" do
    `crystal run spec/clim/readme/files/io_in_run_block.cr --no-color -- `.should eq <<-DISPLAY
    in main

    DISPLAY
  end
end
