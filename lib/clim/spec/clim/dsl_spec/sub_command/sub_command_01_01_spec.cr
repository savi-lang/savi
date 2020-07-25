require "./sub_command"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                      Command Line Interface Tool.

                      Usage:

                        main_of_clim_library [options] [arguments]

                      Options:

                        --help                           Show this help.
                        -v, --version                    Show version.

                      Sub Commands:

                        sub_command_1   Command Line Interface Tool.
                        sub_command_2   Command Line Interface Tool.


                    HELP_MESSAGE

  sub_1_help_message = <<-HELP_MESSAGE

                      Command Line Interface Tool.

                      Usage:

                        sub_command_1 [options] [arguments]

                      Options:

                        -a ARG, --array=ARG              Option test. [type:Array(String)] [default:["default string"]]
                        --help                           Show this help.
                        -v, --version                    Show version.

                      Sub Commands:

                        sub_sub_command_1   Command Line Interface Tool.


                    HELP_MESSAGE
%}

spec_for_sub_command(
  spec_class_name: SubCommandWithDescUsageVersionOption,
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_args_value: [] of String,
    },
    {
      argv:        ["arg1"],
      expect_help: {{main_help_message}},
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["arg1", "arg2"],
      expect_help: {{main_help_message}},
      expect_args_value: ["arg1", "arg2"],
    },
    {
      argv:        ["arg1", "arg2", "arg3"],
      expect_help: {{main_help_message}},
      expect_args_value: ["arg1", "arg2", "arg3"],
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
    {
      argv:        ["sub_command_1"],
      expect_help: {{sub_1_help_message}},
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command_1", "arg1"],
      expect_help: {{sub_1_help_message}},
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["sub_command_1", "arg1", "arg2"],
      expect_help: {{sub_1_help_message}},
      expect_args_value: ["arg1", "arg2"],
    },
    {
      argv:        ["sub_command_1", "arg1", "arg2", "arg3"],
      expect_help: {{sub_1_help_message}},
      expect_args_value: ["arg1", "arg2", "arg3"],
    },
    {
      argv:           ["sub_command_1", "--version"],
      expect_version: "version 1.0.0\n",
    },
    {
      argv:           ["sub_command_1", "-v"],
      expect_version: "version 1.0.0\n",
    },
    {
      argv:              ["sub_command_1", "--help", "-ignore-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["sub_command_1", "-ignore-option", "--help"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["sub_command_1", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command_1", "--missing-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--missing-option\"",
      }
    },
    {
      argv:              ["sub_command_1", "-m", "arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command_1", "arg1", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command_1", "-m", "-d"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:        ["sub_command_1", "--help"],
      expect_help: {{sub_1_help_message}},
    },
    {
      argv:        ["sub_command_1", "--help", "ignore-arg"],
      expect_help: {{sub_1_help_message}},
    },
    {
      argv:        ["sub_command_1", "ignore-arg", "--help"],
      expect_help: {{sub_1_help_message}},
    },
  ]
)
{% end %}
