require "./sub_command_alias"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          --help                           Show this help.

                        Sub Commands:

                          sub_command_1, alias_sub_command_1                               Command Line Interface Tool.
                          sub_command_2, alias_sub_command_2, alias_sub_command_2_second   Command Line Interface Tool.


                      HELP_MESSAGE

  sub_1_help_message = <<-HELP_MESSAGE

                         Command Line Interface Tool.

                         Usage:

                           sub_command_1 [options] [arguments]

                         Options:

                           -a ARG, --array=ARG              Option test. [type:Array(String)] [default:["default string"]]
                           --help                           Show this help.

                         Sub Commands:

                           sub_sub_command_1   Command Line Interface Tool.


                       HELP_MESSAGE

  sub_sub_1_help_message = <<-HELP_MESSAGE

                             Command Line Interface Tool.

                             Usage:

                               sub_sub_command_1 [options] [arguments]

                             Options:

                               -b, --bool                       Bool test. [type:Bool]
                               --help                           Show this help.


                           HELP_MESSAGE

  sub_2_help_message = <<-HELP_MESSAGE

                         Command Line Interface Tool.

                         Usage:

                           sub_command_2 [options] [arguments]

                         Options:

                           --help                           Show this help.


                       HELP_MESSAGE
%}

spec_for_alias_name(
  spec_class_name: SubSubCommandWithAliasName,
  spec_cases: [
    {
      argv:        ["sub_command_1", "sub_sub_command_1"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => false,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["alias_sub_command_1", "sub_sub_command_1"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => false,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command_1", "sub_sub_command_1", "arg1"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => false,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["alias_sub_command_1", "sub_sub_command_1", "arg1"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => false,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["sub_command_1", "sub_sub_command_1", "-b"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["alias_sub_command_1", "sub_sub_command_1", "-b"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command_1", "sub_sub_command_1", "--bool"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["alias_sub_command_1", "sub_sub_command_1", "--bool"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command_1", "sub_sub_command_1", "-b", "arg1"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["alias_sub_command_1", "sub_sub_command_1", "-b", "arg1"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["sub_command_1", "sub_sub_command_1", "--bool", "arg1"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["alias_sub_command_1", "sub_sub_command_1", "--bool", "arg1"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["sub_command_1", "sub_sub_command_1", "arg1", "-b"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["alias_sub_command_1", "sub_sub_command_1", "arg1", "-b"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["sub_command_1", "sub_sub_command_1", "arg1", "--bool"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["alias_sub_command_1", "sub_sub_command_1", "arg1", "--bool"],
      expect_help: {{sub_sub_1_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: ["arg1"],
    },
  ]
)
{% end %}
