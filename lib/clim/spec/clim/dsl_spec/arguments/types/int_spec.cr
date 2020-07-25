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

                          01. arg-int-8       int8 argument. [type:Int8]
                          02. arg-int-16      int16 argument. [type:Int16]
                          03. arg-int-32      int32 argument. [type:Int32]
                          04. arg-int-64      int64 argument. [type:Int64]


                      HELP_MESSAGE
%}

spec(
  spec_class_name: ArgumentTypeSpec,
  spec_dsl_lines: [
    "argument \"arg-int-8\",  type: Int8,  desc: \"int8 argument.\"",
    "argument \"arg-int-16\", type: Int16, desc: \"int16 argument.\"",
    "argument \"arg-int-32\", type: Int32, desc: \"int32 argument.\"",
    "argument \"arg-int-64\", type: Int64, desc: \"int64 argument.\"",
    "option \"-a ARG\", \"--array=ARG\", type: Array(String)",
  ],
  spec_desc: "argument type spec,",
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Int8?,
          "method" => "arg_int_8",
          "expect_value" => nil,
        },
        {
          "type" => Int16?,
          "method" => "arg_int_16",
          "expect_value" => nil,
        },
        {
          "type" => Int32?,
          "method" => "arg_int_32",
          "expect_value" => nil,
        },
        {
          "type" => Int64?,
          "method" => "arg_int_64",
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
      argv:        ["1"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Int8?,
          "method" => "arg_int_8",
          "expect_value" => 1,
        },
        {
          "type" => Int16?,
          "method" => "arg_int_16",
          "expect_value" => nil,
        },
        {
          "type" => Int32?,
          "method" => "arg_int_32",
          "expect_value" => nil,
        },
        {
          "type" => Int64?,
          "method" => "arg_int_64",
          "expect_value" => nil,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["1"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["1"],
        },
      ],
    },
    {
      argv:        ["1", "2"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Int8?,
          "method" => "arg_int_8",
          "expect_value" => 1,
        },
        {
          "type" => Int16?,
          "method" => "arg_int_16",
          "expect_value" => 2,
        },
        {
          "type" => Int32?,
          "method" => "arg_int_32",
          "expect_value" => nil,
        },
        {
          "type" => Int64?,
          "method" => "arg_int_64",
          "expect_value" => nil,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["1", "2"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["1", "2"],
        },
      ],
    },
    {
      argv:        ["1", "2", "3"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Int8?,
          "method" => "arg_int_8",
          "expect_value" => 1,
        },
        {
          "type" => Int16?,
          "method" => "arg_int_16",
          "expect_value" => 2,
        },
        {
          "type" => Int32?,
          "method" => "arg_int_32",
          "expect_value" => 3,
        },
        {
          "type" => Int64?,
          "method" => "arg_int_64",
          "expect_value" => nil,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["1", "2", "3"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["1", "2", "3"],
        },
      ],
    },
    {
      argv:        ["1", "2", "3", "4"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Int8?,
          "method" => "arg_int_8",
          "expect_value" => 1,
        },
        {
          "type" => Int16?,
          "method" => "arg_int_16",
          "expect_value" => 2,
        },
        {
          "type" => Int32?,
          "method" => "arg_int_32",
          "expect_value" => 3,
        },
        {
          "type" => Int64?,
          "method" => "arg_int_64",
          "expect_value" => 4,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["1", "2", "3", "4"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["1", "2", "3", "4"],
        },
      ],
    },
    {
      argv:        ["1", "2", "--array", "array_value", "3", "4", "5"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Int8?,
          "method" => "arg_int_8",
          "expect_value" => 1,
        },
        {
          "type" => Int16?,
          "method" => "arg_int_16",
          "expect_value" => 2,
        },
        {
          "type" => Int32?,
          "method" => "arg_int_32",
          "expect_value" => 3,
        },
        {
          "type" => Int64?,
          "method" => "arg_int_64",
          "expect_value" => 4,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["1", "2", "3", "4", "5"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => ["5"],
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["1", "2", "--array", "array_value", "3", "4", "5"],
        },
      ],
    },
    {
      argv:              ["foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int8: foo",
      }
    },
    {
      argv:              ["1", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int16: foo",
      }
    },
    {
      argv:              ["1", "2", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int32: foo",
      }
    },
    {
      argv:              ["1", "2", "3", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int64: foo",
      }
    },
  ]
)
{% end %}
