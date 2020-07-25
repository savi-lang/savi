require "../../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          --bool                           Option description. [type:Bool]
                          --bool-equal=BOOL                Option description. [type:Bool]
                          --bool-default                   Option description. [type:Bool] [default:false]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: OptionTypeSpec,
  spec_dsl_lines: [
    "option \"--bool\", type: Bool",
    "option \"--bool-equal=BOOL\", type: Bool",
    "option \"--bool-default\", type: Bool, default: false",
  ],
  spec_desc: "option type spec,",
  spec_cases: [
    # ====================================================
    # Bool
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => false,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--bool"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool",
        "expect_value" => true,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool_equal",
        "expect_value" => false,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--bool-equal=false"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool_equal",
        "expect_value" => false,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--bool-equal=true"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool_equal",
        "expect_value" => true,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--bool-equal=foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Bool arguments accept only \"true\" or \"false\". Input: [foo]",
      }
    },
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool_default",
        "expect_value" => false,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--bool-default"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "bool_default",
        "expect_value" => true,
      },
      expect_args_value: [] of String,
    },
  ]
)
{% end %}
