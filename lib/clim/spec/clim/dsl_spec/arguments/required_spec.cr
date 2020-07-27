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

                          01. arg1      1 argument. [type:String]
                          02. arg2      2 argument. [type:String]
                          03. arg3      3 argument. [type:String] [required]
                          04. arg4      4 argument. [type:String] [required]
                          05. arg5      5 argument. [type:String]


                      HELP_MESSAGE
%}

spec(
  spec_class_name: ArgumentTypeSpec,
  spec_dsl_lines: [
    "option \"-a ARG\", \"--array=ARG\", type: Array(String)",
    "argument \"arg1\", type: String, desc: \"1 argument.\"",
    "argument \"arg2\", type: String, desc: \"2 argument.\"",
    "argument \"arg3\", type: String, desc: \"3 argument.\", required: true",
    "argument \"arg4\", type: String, desc: \"4 argument.\", required: true",
    "argument \"arg5\", type: String, desc: \"5 argument.\"",
  ],
  spec_desc: "argument type spec,",
  spec_cases: [
    {
      argv:              [] of String,
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Required arguments. \"arg3\", \"arg4\"",
      },
    },
    {
      argv:              ["value1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Required arguments. \"arg3\", \"arg4\"",
      },
    },
    {
      argv:              ["value1", "value2"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Required arguments. \"arg3\", \"arg4\"",
      },
    },
    {
      argv:              ["value1", "value2", "value3"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Required arguments. \"arg4\"",
      }
    },
    {
      argv: ["value1", "value2", "value3", "value4"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => String?,
          "method" => "arg1",
          "expect_value" => "value1",
        },
        {
          "type" => String?,
          "method" => "arg2",
          "expect_value" => "value2",
        },
        {
          "type" => String,
          "method" => "arg3",
          "expect_value" => "value3",
        },
        {
          "type" => String,
          "method" => "arg4",
          "expect_value" => "value4",
        },
        {
          "type" => String?,
          "method" => "arg5",
          "expect_value" => nil,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["value1", "value2", "value3", "value4"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["value1", "value2", "value3", "value4"],
        },
      ],
    },
    {
      argv: ["value1", "value2", "value3", "value4", "value5"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => String?,
          "method" => "arg1",
          "expect_value" => "value1",
        },
        {
          "type" => String?,
          "method" => "arg2",
          "expect_value" => "value2",
        },
        {
          "type" => String,
          "method" => "arg3",
          "expect_value" => "value3",
        },
        {
          "type" => String,
          "method" => "arg4",
          "expect_value" => "value4",
        },
        {
          "type" => String?,
          "method" => "arg5",
          "expect_value" => "value5",
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["value1", "value2", "value3", "value4", "value5"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["value1", "value2", "value3", "value4", "value5"],
        },
      ],
    },
    {
      argv: ["value1", "value2", "--array", "array_value", "value3", "value4", "value5", "value6", "value7"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => String?,
          "method" => "arg1",
          "expect_value" => "value1",
        },
        {
          "type" => String?,
          "method" => "arg2",
          "expect_value" => "value2",
        },
        {
          "type" => String,
          "method" => "arg3",
          "expect_value" => "value3",
        },
        {
          "type" => String,
          "method" => "arg4",
          "expect_value" => "value4",
        },
        {
          "type" => String?,
          "method" => "arg5",
          "expect_value" => "value5",
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["value1", "value2", "value3", "value4", "value5", "value6", "value7"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => ["value6", "value7"],
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["value1", "value2", "--array", "array_value", "value3", "value4", "value5", "value6", "value7"],
        },
      ],
    },
  ]
)
{% end %}
