require "../../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          -d=DEFAULT_TYPE                  Option description. [type:String]
                          --default-type=DEFAULT_TYPE      Option description. [type:String]
                          --default-type-default=DEFAULT_TYPE
                                                           Option description. [type:String] [default:"Default String!"]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: OptionTypeSpec,
  spec_dsl_lines: [
    "option \"-d=DEFAULT_TYPE\"",
    "option \"--default-type=DEFAULT_TYPE\"",
    "option \"--default-type-default=DEFAULT_TYPE\", default: \"Default String!\"",
  ],
  spec_desc: "option type spec,",
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String?,
        "method" => "d",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-d", "foo", "bar"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String?,
        "method" => "d",
        "expect_value" => "foo",
      },
      expect_args_value: ["bar"]
    },
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String?,
        "method" => "default_type",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--default-type", "foo", "bar"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String?,
        "method" => "default_type",
        "expect_value" => "foo",
      },
      expect_args_value: ["bar"]
    },
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String,
        "method" => "default_type_default",
        "expect_value" => "Default String!",
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--default-type-default", "foo", "bar"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String,
        "method" => "default_type_default",
        "expect_value" => "foo",
      },
      expect_args_value: ["bar"]
    },
  ]
)
{% end %}
