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

                          01. arg-float-32      float32 argument. [type:Float32]
                          02. arg-float-64      float64 argument. [type:Float64]


                      HELP_MESSAGE
%}

spec(
  spec_class_name: ArgumentTypeSpec,
  spec_dsl_lines: [
    "argument \"arg-float-32\", type: Float32, desc: \"float32 argument.\"",
    "argument \"arg-float-64\", type: Float64, desc: \"float64 argument.\"",
    "option \"-a ARG\", \"--array=ARG\", type: Array(String)",
  ],
  spec_desc: "argument type spec,",
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Float32?,
          "method" => "arg_float_32",
          "expect_value" => nil,
        },
        {
          "type" => Float64?,
          "method" => "arg_float_64",
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
      argv:        ["1.1"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Float32?,
          "method" => "arg_float_32",
          "expect_value" => 1.1f32,
        },
        {
          "type" => Float64?,
          "method" => "arg_float_64",
          "expect_value" => nil,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["1.1"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["1.1"],
        },
      ],
    },
    {
      argv:        ["1.1", "2.2"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Float32?,
          "method" => "arg_float_32",
          "expect_value" => 1.1f32,
        },
        {
          "type" => Float64?,
          "method" => "arg_float_64",
          "expect_value" => 2.2f64,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["1.1", "2.2"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => [] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["1.1", "2.2"],
        },
      ],
    },
    {
      argv:        ["1.1", "2.2", "3.3"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Float32?,
          "method" => "arg_float_32",
          "expect_value" => 1.1f32,
        },
        {
          "type" => Float64?,
          "method" => "arg_float_64",
          "expect_value" => 2.2f64,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["1.1", "2.2", "3.3"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => ["3.3"] of String,
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["1.1", "2.2", "3.3"],
        },
      ],
    },
    {
      argv:        ["1.1", "2.2", "--array", "array_value", "3.3", "4.4"],
      expect_help: {{main_help_message}},
      expect_args: [
        {
          "type" => Float32?,
          "method" => "arg_float_32",
          "expect_value" => 1.1f32,
        },
        {
          "type" => Float64?,
          "method" => "arg_float_64",
          "expect_value" => 2.2f64,
        },
        {
          "type" => Array(String),
          "method" => "all_args",
          "expect_value" => ["1.1", "2.2", "3.3", "4.4"],
        },
        {
          "type" => Array(String),
          "method" => "unknown_args",
          "expect_value" => ["3.3", "4.4"],
        },
        {
          "type" => Array(String),
          "method" => "argv",
          "expect_value" => ["1.1", "2.2", "--array", "array_value", "3.3", "4.4"],
        },
      ],
    },
    {
      argv:              ["foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Float32: foo",
      }
    },
    {
      argv:              ["1.1", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Float64: foo",
      }
    },
  ]
)
{% end %}
