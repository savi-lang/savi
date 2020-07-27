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

                          01. arg-uint-8       uint8 argument. [type:UInt8]
                          02. arg-uint-16      uint16 argument. [type:UInt16]
                          03. arg-uint-32      uint32 argument. [type:UInt32]
                          04. arg-uint-64      uint64 argument. [type:UInt64]


                      HELP_MESSAGE
%}

spec(
  spec_class_name: ArgumentTypeSpec,
  spec_dsl_lines: [
    "argument \"arg-uint-8\",  type: UInt8,  desc: \"uint8 argument.\"",
    "argument \"arg-uint-16\", type: UInt16, desc: \"uint16 argument.\"",
    "argument \"arg-uint-32\", type: UInt32, desc: \"uint32 argument.\"",
    "argument \"arg-uint-64\", type: UInt64, desc: \"uint64 argument.\"",
    "option \"-a ARG\", \"--array=ARG\", type: Array(String)",
  ],
  spec_desc: "argument type spec,",
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => UInt8?,
          "method" => "arg_uint_8",
          "expect_value" => nil,
        },
        {
          "type" => UInt16?,
          "method" => "arg_uint_16",
          "expect_value" => nil,
        },
        {
          "type" => UInt32?,
          "method" => "arg_uint_32",
          "expect_value" => nil,
        },
        {
          "type" => UInt64?,
          "method" => "arg_uint_64",
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
          "type" => UInt8?,
          "method" => "arg_uint_8",
          "expect_value" => 1,
        },
        {
          "type" => UInt16?,
          "method" => "arg_uint_16",
          "expect_value" => nil,
        },
        {
          "type" => UInt32?,
          "method" => "arg_uint_32",
          "expect_value" => nil,
        },
        {
          "type" => UInt64?,
          "method" => "arg_uint_64",
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
          "type" => UInt8?,
          "method" => "arg_uint_8",
          "expect_value" => 1,
        },
        {
          "type" => UInt16?,
          "method" => "arg_uint_16",
          "expect_value" => 2,
        },
        {
          "type" => UInt32?,
          "method" => "arg_uint_32",
          "expect_value" => nil,
        },
        {
          "type" => UInt64?,
          "method" => "arg_uint_64",
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
          "type" => UInt8?,
          "method" => "arg_uint_8",
          "expect_value" => 1,
        },
        {
          "type" => UInt16?,
          "method" => "arg_uint_16",
          "expect_value" => 2,
        },
        {
          "type" => UInt32?,
          "method" => "arg_uint_32",
          "expect_value" => 3,
        },
        {
          "type" => UInt64?,
          "method" => "arg_uint_64",
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
          "type" => UInt8?,
          "method" => "arg_uint_8",
          "expect_value" => 1,
        },
        {
          "type" => UInt16?,
          "method" => "arg_uint_16",
          "expect_value" => 2,
        },
        {
          "type" => UInt32?,
          "method" => "arg_uint_32",
          "expect_value" => 3,
        },
        {
          "type" => UInt64?,
          "method" => "arg_uint_64",
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
          "type" => UInt8?,
          "method" => "arg_uint_8",
          "expect_value" => 1,
        },
        {
          "type" => UInt16?,
          "method" => "arg_uint_16",
          "expect_value" => 2,
        },
        {
          "type" => UInt32?,
          "method" => "arg_uint_32",
          "expect_value" => 3,
        },
        {
          "type" => UInt64?,
          "method" => "arg_uint_64",
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
        message:   "Invalid UInt8: foo",
      }
    },
    {
      argv:              ["1", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid UInt16: foo",
      }
    },
    {
      argv:              ["1", "2", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid UInt32: foo",
      }
    },
    {
      argv:              ["1", "2", "3", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid UInt64: foo",
      }
    },
  ]
)
{% end %}
