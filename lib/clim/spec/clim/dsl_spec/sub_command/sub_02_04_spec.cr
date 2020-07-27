require "../../dsl_spec"

macro spec_for_alias_name(spec_class_name, spec_cases)
  {% for spec_case, index in spec_cases %}
    {% class_name = (spec_class_name.stringify + index.stringify).id %}

    # define dsl
    class {{class_name}} < Clim
      main do
        run do |opts, args|
          assert_opts_and_args({{spec_case}})
        end
        sub "sub_command_1" do
          alias_name "alias_sub_command_1"
          run do |opts, args|
            assert_opts_and_args({{spec_case}})
          end
          sub "sub_sub_command_1" do
            run do |opts, args|
            end
          end
        end
        sub "sub_command_2" do
          alias_name "alias_sub_command_2", "alias_sub_command_2_second"
          run do |opts, args|
            assert_opts_and_args({{spec_case}})
          end
        end
      end
    end

    # spec
    describe "alias name case," do
      describe "if argv is " + {{spec_case["argv"].stringify}} + "," do
        it_blocks({{class_name}}, {{spec_case}})
      end
    end
  {% end %}
end

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

                           --help                           Show this help.

                         Sub Commands:

                           sub_sub_command_1   Command Line Interface Tool.


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
  spec_class_name: SubCommandWithAliasName,
  spec_cases: [
    {
      argv:              ["sub_command_2", "--help", "-ignore-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["alias_sub_command_2", "--help", "-ignore-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["alias_sub_command_2_second", "--help", "-ignore-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["sub_command_2", "-ignore-option", "--help"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["alias_sub_command_2", "-ignore-option", "--help"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["alias_sub_command_2_second", "-ignore-option", "--help"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["sub_command_2", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_2", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_2_second", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command_2", "--missing-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--missing-option\"",
      }
    },
    {
      argv:              ["alias_sub_command_2", "--missing-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--missing-option\"",
      }
    },
    {
      argv:              ["alias_sub_command_2_second", "--missing-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--missing-option\"",
      }
    },
    {
      argv:              ["sub_command_2", "-m", "arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_2", "-m", "arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_2_second", "-m", "arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command_2", "arg1", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_2", "arg1", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_2_second", "arg1", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command_2", "-m", "-d"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_2", "-m", "-d"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["alias_sub_command_2_second", "-m", "-d"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
  ]
)
{% end %}
