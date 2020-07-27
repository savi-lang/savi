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
  spec_class_name: SubCommandWithAliasName,
  spec_cases: [
    {
      argv:        ["sub_command_1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["default string"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["alias_sub_command_1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["default string"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command_1", "arg1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["default string"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["alias_sub_command_1", "arg1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["default string"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["sub_command_1", "-a", "array1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["alias_sub_command_1", "-a", "array1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command_1", "-a", "array1", "arg1", "-a", "array2"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1", "array2"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["alias_sub_command_1", "-a", "array1", "arg1", "-a", "array2"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1", "array2"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["sub_command_1", "-aarray1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["alias_sub_command_1", "-aarray1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command_1", "--array", "array1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["alias_sub_command_1", "--array", "array1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command_1", "--array=array1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["alias_sub_command_1", "--array=array1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command_1", "-a", "array1", "arg1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["alias_sub_command_1", "-a", "array1", "arg1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["sub_command_1", "arg1", "-a", "array1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["alias_sub_command_1", "arg1", "-a", "array1"],
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["sub_command_1", "-array"], # Unintended case.
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["rray"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["alias_sub_command_1", "-array"], # Unintended case.
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["rray"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command_1", "-a=array1"], # Unintended case.
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["=array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["alias_sub_command_1", "-a=array1"], # Unintended case.
      expect_help: {{sub_1_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["=array1"],
      },
      expect_args_value: [] of String,
    },
  ]
)
{% end %}
