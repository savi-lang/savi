require "../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                       Command Line Interface Tool.

                       Usage:

                         main_of_clim_library [options] [arguments]

                       Options:

                         -b ARG                           Option description. [type:Bool]
                         --help                           Show this help.


                     HELP_MESSAGE
%}

spec(
  spec_class_name: MainCommandWithBoolArgumentsOnlyShortOption,
  spec_dsl_lines: [
    "option \"-b ARG\", type: Bool",
  ],
  spec_desc: "main command with Bool option,",
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "b",
        "expect_value" => false,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["arg1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "b",
        "expect_value" => false,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["-b", "true"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "b",
        "expect_value" => true,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-b", "false"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Bool,
        "method" => "b",
        "expect_value" => false,
      },
      expect_args_value: [] of String,
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
      argv:              ["-b"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"-b\"",
      }
    },
    {
      argv:              ["--bool"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--bool\"",
      }
    },
    {
      argv:              ["--bool", "true"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--bool\"",
      }
    },
    {
      argv:              ["--bool", "false"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--bool\"",
      }
    },
    {
      argv:              ["arg1", "-b"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"-b\"",
      }
    },
    {
      argv:              ["arg1", "--bool"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--bool\"",
      }
    },
    {
      argv:              ["-b", "arg1"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Bool arguments accept only \"true\" or \"false\". Input: [arg1]",
      }
    },
    {
      argv:              ["--bool=arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--bool=arg1\"",
      }
    },
    {
      argv:              ["--b"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--b\"",
      }
    },
    {
      argv:              ["-bool"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Bool arguments accept only \"true\" or \"false\". Input: [ool]",
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
