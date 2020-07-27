require "./sub_command_alias"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          --help                           Show this help.

                        Sub Commands:

                          sub_command_1, alias_sub_command_1                               Command Line Interface Tool.
                          sub_command_2, alias_sub_command_2, alias_sub_command_2_second   Command Line Interface Tool.


                      HELP_MESSAGE

  sub_1_help_message = <<-HELP_MESSAGE

                         Command Line Interface Tool.

                         Usage:

                           sub_command_1 [options] [arguments]

                         Options:

                           -a ARG, --array=ARG              Option test. [type:Array(String)] [default:["default string"]]
                           --help                           Show this help.

                         Sub Commands:

                           sub_sub_command_1   Command Line Interface Tool.


                       HELP_MESSAGE

  sub_sub_1_help_message = <<-HELP_MESSAGE

                             Command Line Interface Tool.

                             Usage:

                               sub_sub_command_1 [options] [arguments]

                             Options:

                               -b, --bool                       Bool test. [type:Bool]
                               --help                           Show this help.


                           HELP_MESSAGE

  sub_2_help_message = <<-HELP_MESSAGE

                         Command Line Interface Tool.

                         Usage:

                           sub_command_2 [options] [arguments]

                         Options:

                           --help                           Show this help.


                       HELP_MESSAGE
%}

spec_for_alias_name(
  spec_class_name: SubSubCommandWithAliasName,
  spec_cases: [
    {
      argv:              ["sub_command_1", "sub_sub_command_1", "--help", "-ignore-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["alias_sub_command_1", "sub_sub_command_1", "--help", "-ignore-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["sub_command_1", "sub_sub_command_1", "-ignore-option", "--help"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["alias_sub_command_1", "sub_sub_command_1", "-ignore-option", "--help"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["sub_command_1", "sub_sub_command_1", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_1", "sub_sub_command_1", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command_1", "sub_sub_command_1", "--missing-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--missing-option\"",
      }
    },
    {
      argv:              ["alias_sub_command_1", "sub_sub_command_1", "--missing-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--missing-option\"",
      }
    },
    {
      argv:              ["sub_command_1", "sub_sub_command_1", "-m", "arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_1", "sub_sub_command_1", "-m", "arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command_1", "sub_sub_command_1", "arg1", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_1", "sub_sub_command_1", "arg1", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command_1", "sub_sub_command_1", "-m", "-d"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_1", "sub_sub_command_1", "-m", "-d"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:        ["sub_command_1", "sub_sub_command_1", "--help"],
      expect_help: {{sub_sub_1_help_message}},
    },
    {
      argv:        ["alias_sub_command_1", "sub_sub_command_1", "--help"],
      expect_help: {{sub_sub_1_help_message}},
    },
    {
      argv:        ["sub_command_1", "sub_sub_command_1", "--help", "ignore-arg"],
      expect_help: {{sub_sub_1_help_message}},
    },
    {
      argv:        ["alias_sub_command_1", "sub_sub_command_1", "--help", "ignore-arg"],
      expect_help: {{sub_sub_1_help_message}},
    },
    {
      argv:        ["sub_command_1", "sub_sub_command_1", "ignore-arg", "--help"],
      expect_help: {{sub_sub_1_help_message}},
    },
    {
      argv:        ["alias_sub_command_1", "sub_sub_command_1", "ignore-arg", "--help"],
      expect_help: {{sub_sub_1_help_message}},
    },
  ]
)
{% end %}
