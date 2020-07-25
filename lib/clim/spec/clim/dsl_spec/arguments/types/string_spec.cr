require "../../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          -a ARG, --array=ARG              Option description. [type:Array(String)]
                          --help                           Show this help.

                        Arguments:

                          01. arg1a        first argument. [type:String]
                          02. arg2ab       second argument. [type:String]
                          03. arg3abc      third argument. [type:String]


                      HELP_MESSAGE
%}

spec(
  spec_class_name: ArgumentTypeSpec,
  spec_dsl_lines: [
    "argument \"arg1a\", type: String, desc: \"first argument.\"",
    "argument \"arg2ab\", type: String, desc: \"second argument.\"",
    "argument \"arg3abc\", type: String, desc: \"third argument.\"",
    "option \"-a ARG\", \"--array=ARG\", type: Array(String)",
  ],
  spec_desc: "argument type spec,",
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => String?,
          "method" => "arg1a",
          "expect_value" => nil,
        },
        {
          "type" => String?,
          "method" => "arg2ab",
          "expect_value" => nil,
        },
        {
          "type" => String?,
          "method" => "arg3abc",
          "expect_value" => nil,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => [] of String,
        },
      ],
    },
    {
      argv:        ["value1"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => String?,
          "method" => "arg1a",
          "expect_value" => "value1",
        },
        {
          "type" => String?,
          "method" => "arg2ab",
          "expect_value" => nil,
        },
        {
          "type" => String?,
          "method" => "arg3abc",
          "expect_value" => nil,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["value1"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["value1"],
        },
      ],
    },
    {
      argv:        ["value1", "value2"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => String?,
          "method" => "arg1a",
          "expect_value" => "value1",
        },
        {
          "type" => String?,
          "method" => "arg2ab",
          "expect_value" => "value2",
        },
        {
          "type" => String?,
          "method" => "arg3abc",
          "expect_value" => nil,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["value1", "value2"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["value1", "value2"],
        },
      ],
    },
    {
      argv:        ["value1", "value2", "value3"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => String?,
          "method" => "arg1a",
          "expect_value" => "value1",
        },
        {
          "type" => String?,
          "method" => "arg2ab",
          "expect_value" => "value2",
        },
        {
          "type" => String?,
          "method" => "arg3abc",
          "expect_value" => "value3",
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["value1", "value2", "value3"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["value1", "value2", "value3"],
        },
      ],
    },
    {
      argv:        ["value1", "value2", "value3", "value4"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => String?,
          "method" => "arg1a",
          "expect_value" => "value1",
        },
        {
          "type" => String?,
          "method" => "arg2ab",
          "expect_value" => "value2",
        },
        {
          "type" => String?,
          "method" => "arg3abc",
          "expect_value" => "value3",
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["value1", "value2", "value3", "value4"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => ["value4"],
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["value1", "value2", "value3", "value4"],
        },
      ],
    },
    {
      argv:        ["value1", "value2", "--array", "array_value", "value3", "value4", "value5"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => String?,
          "method" => "arg1a",
          "expect_value" => "value1",
        },
        {
          "type" => String?,
          "method" => "arg2ab",
          "expect_value" => "value2",
        },
        {
          "type" => String?,
          "method" => "arg3abc",
          "expect_value" => "value3",
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["value1", "value2", "value3", "value4", "value5"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => ["value4", "value5"],
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["value1", "value2", "--array", "array_value", "value3", "value4", "value5"],
        },
      ],
    },
  ]
)
{% end %}
