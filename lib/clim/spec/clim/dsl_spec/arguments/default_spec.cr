require "../../dsl_spec"

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

                          01. arg1      first argument. [type:String]
                          02. arg2      second argument. [type:String] [default:"default value"]
                          03. arg3      third argument. [type:String]


                      HELP_MESSAGE
%}

spec(
  spec_class_name: ArgumentTypeSpec,
  spec_dsl_lines: [
    "option \"-a ARG\", \"--array=ARG\", type: Array(String)",
    "argument \"arg1\", type: String, desc: \"first argument.\"",
    "argument \"arg2\", type: String, desc: \"second argument.\", default: \"default value\"",
    "argument \"arg3\", type: String, desc: \"third argument.\"",
  ],
  spec_desc: "argument type spec,",
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => String?,
          "method" => "arg1",
          "expect_value" => nil,
        },
        {
          "type" => String,
          "method" => "arg2",
          "expect_value" => "default value",
        },
        {
          "type" => String?,
          "method" => "arg3",
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
          "method" => "arg1",
          "expect_value" => "value1",
        },
        {
          "type" => String,
          "method" => "arg2",
          "expect_value" => "default value",
        },
        {
          "type" => String?,
          "method" => "arg3",
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
          "method" => "arg1",
          "expect_value" => "value1",
        },
        {
          "type" => String,
          "method" => "arg2",
          "expect_value" => "value2",
        },
        {
          "type" => String?,
          "method" => "arg3",
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
          "method" => "arg1",
          "expect_value" => "value1",
        },
        {
          "type" => String,
          "method" => "arg2",
          "expect_value" => "value2",
        },
        {
          "type" => String?,
          "method" => "arg3",
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
          "method" => "arg1",
          "expect_value" => "value1",
        },
        {
          "type" => String,
          "method" => "arg2",
          "expect_value" => "value2",
        },
        {
          "type" => String?,
          "method" => "arg3",
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
          "method" => "arg1",
          "expect_value" => "value1",
        },
        {
          "type" => String,
          "method" => "arg2",
          "expect_value" => "value2",
        },
        {
          "type" => String?,
          "method" => "arg3",
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
