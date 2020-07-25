require "../../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          --float32=VALUE                  Option description. [type:Float32]
                          --float64=VALUE                  Option description. [type:Float64]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: OptionTypeSpec,
  spec_dsl_lines: [
    "option \"--float32=VALUE\", type: Float32",
    "option \"--float64=VALUE\", type: Float64",
  ],
  spec_desc: "option type spec,",
  spec_cases: [
    # ====================================================
    # Float32
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Float32?,
        "method" => "float32",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--float32", "5.5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Float32?,
        "method" => "float32",
        "expect_value" => 5.5_f32,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--float32", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Float32: foo",
      }
    },

    # ====================================================
    # Float64
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Float64?,
        "method" => "float64",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--float64", "5.5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Float64?,
        "method" => "float64",
        "expect_value" => 5.5_f64,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--float64", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Float64: foo",
      }
    },
  ]
)
{% end %}
