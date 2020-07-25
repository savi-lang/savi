require "../../../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          --array-string=VALUE             Option description. [type:Array(String)]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: OptionTypeSpec,
  spec_dsl_lines: [
    "option \"--array-string=VALUE\", type: Array(String)",
  ],
  spec_desc: "option type spec,",
  spec_cases: [
    # ====================================================
    # Array(String)
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array_string",
        "expect_value" => [] of String,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-string", "array1", "--array-string", "array2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array_string",
        "expect_value" => ["array1", "array2"],
      },
      expect_args_value: [] of String,
    },
  ]
)
{% end %}
