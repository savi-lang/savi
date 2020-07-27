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

                          01. arg1a        first argument. [type:Bool]
                          02. arg2ab       second argument. [type:Bool]
                          03. arg3abc      third argument. [type:Bool]


                      HELP_MESSAGE
%}

spec(
  spec_class_name: ArgumentTypeSpec,
  spec_dsl_lines: [
    "argument \"arg1a\", type: Bool, desc: \"first argument.\"",
    "argument \"arg2ab\", type: Bool, desc: \"second argument.\"",
    "argument \"arg3abc\", type: Bool, desc: \"third argument.\"",
    "option \"-a ARG\", \"--array=ARG\", type: Array(String)",
  ],
  spec_desc: "argument type spec,",
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Bool?,
          "method" => "arg1a",
          "expect_value" => nil,
        },
        {
          "type" => Bool?,
          "method" => "arg2ab",
          "expect_value" => nil,
        },
        {
          "type" => Bool?,
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
      argv:        ["true"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Bool?,
          "method" => "arg1a",
          "expect_value" => true,
        },
        {
          "type" => Bool?,
          "method" => "arg2ab",
          "expect_value" => nil,
        },
        {
          "type" => Bool?,
          "method" => "arg3abc",
          "expect_value" => nil,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["true"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["true"],
        },
      ],
    },
    {
      argv:        ["true", "false"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Bool?,
          "method" => "arg1a",
          "expect_value" => true,
        },
        {
          "type" => Bool?,
          "method" => "arg2ab",
          "expect_value" => false,
        },
        {
          "type" => Bool?,
          "method" => "arg3abc",
          "expect_value" => nil,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["true", "false"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["true", "false"],
        },
      ],
    },
    {
      argv:        ["true", "false", "true"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Bool?,
          "method" => "arg1a",
          "expect_value" => true,
        },
        {
          "type" => Bool?,
          "method" => "arg2ab",
          "expect_value" => false,
        },
        {
          "type" => Bool?,
          "method" => "arg3abc",
          "expect_value" => true,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["true", "false", "true"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["true", "false", "true"],
        },
      ],
    },
    {
      argv:        ["false", "true", "false", "value4"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Bool?,
          "method" => "arg1a",
          "expect_value" => false,
        },
        {
          "type" => Bool?,
          "method" => "arg2ab",
          "expect_value" => true,
        },
        {
          "type" => Bool?,
          "method" => "arg3abc",
          "expect_value" => false,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["false", "true", "false", "value4"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => ["value4"],
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["false", "true", "false", "value4"],
        },
      ],
    },
    {
      argv:        ["true", "false", "--array", "array_value", "true", "value4", "value5"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Bool?,
          "method" => "arg1a",
          "expect_value" => true,
        },
        {
          "type" => Bool?,
          "method" => "arg2ab",
          "expect_value" => false,
        },
        {
          "type" => Bool?,
          "method" => "arg3abc",
          "expect_value" => true,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["true", "false", "true", "value4", "value5"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => ["value4", "value5"],
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["true", "false", "--array", "array_value", "true", "value4", "value5"],
        },
      ],
    },
    {
      argv:              ["foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Bool arguments accept only \"true\" or \"false\". Input: [foo]",
      }
    },
    {
      argv:              ["true", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Bool arguments accept only \"true\" or \"false\". Input: [foo]",
      }
    },
    {
      argv:              ["true", "false", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Bool arguments accept only \"true\" or \"false\". Input: [foo]",
      }
    },
  ]
)
{% end %}
