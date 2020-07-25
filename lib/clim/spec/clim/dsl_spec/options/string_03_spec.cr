require "../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          --string=ARG                     Option description. [type:String]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: MainCommandWithStringOnlyLongOption,
  spec_dsl_lines: [
    "option \"--string=ARG\", type: String",
  ],
  spec_desc: "main command with String options,",
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String?,
        "method" => "string",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["arg1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String?,
        "method" => "string",
        "expect_value" => nil,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["--string=string1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String?,
        "method" => "string",
        "expect_value" => "string1",
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--string", "string1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String?,
        "method" => "string",
        "expect_value" => "string1",
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--string", "string1", "arg1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String?,
        "method" => "string",
        "expect_value" => "string1",
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["arg1", "--string", "string1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => String?,
        "method" => "string",
        "expect_value" => "string1",
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:              ["-h"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-h\"",
      }
    },
    {
      argv:              ["--help", "-ignore-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["-ignore-option", "--help"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["--string"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"--string\"",
      }
    },
    {
      argv:              ["-s"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-s\"",
      }
    },
    {
      argv:              ["-s", "string1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-s\"",
      }
    },
    {
      argv:              ["-s=string1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-s=string1\"",
      }
    },
    {
      argv:              ["arg1", "--string"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"--string\"",
      }
    },
    {
      argv:        ["--help"],
      expect_help: {{main_help_message}},
    },
    {
      argv:        ["--help", "ignore-arg"],
      expect_help: {{main_help_message}},
    },
    {
      argv:        ["ignore-arg", "--help"],
      expect_help: {{main_help_message}},
    },
  ]
)
{% end %}
