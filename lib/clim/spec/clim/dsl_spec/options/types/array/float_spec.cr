require "../../../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          --array-float32=VALUE            Option description. [type:Array(Float32)]
                          --array-float64=VALUE            Option description. [type:Array(Float64)]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: OptionTypeSpec,
  spec_dsl_lines: [
    "option \"--array-float32=VALUE\", type: Array(Float32)",
    "option \"--array-float64=VALUE\", type: Array(Float64)",
  ],
  spec_desc: "option type spec,",
  spec_cases: [
    # ====================================================
    # Array(Float32)
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Float32),
        "method" => "array_float32",
        "expect_value" => [] of Float32,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-float32", "1.1", "--array-float32", "2.2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Float32),
        "method" => "array_float32",
        "expect_value" => [1.1_f32, 2.2_f32],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-float32", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Float32: foo",
      }
    },

    # ====================================================
    # Array(Float64)
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Float64),
        "method" => "array_float64",
        "expect_value" => [] of Float64,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-float64", "1.1", "--array-float64", "2.2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Float64),
        "method" => "array_float64",
        "expect_value" => [1.1_f64, 2.2_f64],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-float64", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Float64: foo",
      }
    },
  ]
)
{% end %}
