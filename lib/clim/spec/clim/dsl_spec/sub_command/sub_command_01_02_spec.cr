require "../../dsl_spec"

macro spec_for_sub_sub_commands(spec_class_name, spec_cases)
  {% for spec_case, index in spec_cases %}
    {% class_name = (spec_class_name.stringify + index.stringify).id %}

    # define dsl
    class {{class_name}} < Clim
      main do
        run do |opts, args|
          assert_opts_and_args({{spec_case}})
        end
        sub "sub_command" do
          run do |opts, args|
            assert_opts_and_args({{spec_case}})
          end
          sub "sub_sub_command" do
            run do |opts, args|
              assert_opts_and_args({{spec_case}})
            end
          end
        end
      end
    end

    # spec
    describe "sub sub command," do
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

                        sub_command   Command Line Interface Tool.


                    HELP_MESSAGE

  sub_help_message = <<-HELP_MESSAGE

                     Command Line Interface Tool.

                     Usage:

                       sub_command [options] [arguments]

                     Options:

                       --help                           Show this help.

                     Sub Commands:

                       sub_sub_command   Command Line Interface Tool.


                   HELP_MESSAGE

  sub_sub_help_message = <<-HELP_MESSAGE

                         Command Line Interface Tool.

                         Usage:

                           sub_sub_command [options] [arguments]

                         Options:

                           --help                           Show this help.


                       HELP_MESSAGE
%}

spec_for_sub_sub_commands(
  spec_class_name: SubSubCommandOnly,
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
      argv: ["--help"],
      expect_help: {{main_help_message}},
    },
    {
      argv: ["--help", "ignore-arg"],
      expect_help: {{main_help_message}},
    },
    {
      argv: ["ignore-arg", "--help"],
      expect_help: {{main_help_message}},
    },
    {
      argv:        ["sub_command"],
      expect_help: {{sub_help_message}},
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command", "arg1"],
      expect_help: {{sub_help_message}},
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["sub_command", "arg1", "arg2"],
      expect_help: {{sub_help_message}},
      expect_args_value: ["arg1", "arg2"],
    },
    {
      argv:        ["sub_command", "arg1", "arg2", "arg3"],
      expect_help: {{sub_help_message}},
      expect_args_value: ["arg1", "arg2", "arg3"],
    },
    {
      argv:              ["sub_command", "--help", "-ignore-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["sub_command", "-ignore-option", "--help"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["sub_command", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command", "--missing-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--missing-option\"",
      }
    },
    {
      argv:              ["sub_command", "-m", "arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command", "arg1", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command", "-m", "-d"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:        ["sub_command", "--help"],
      expect_help: {{sub_help_message}},
    },
    {
      argv:        ["sub_command", "--help", "ignore-arg"],
      expect_help: {{sub_help_message}},
    },
    {
      argv:        ["sub_command", "ignore-arg", "--help"],
      expect_help: {{sub_help_message}},
    },
    {
      argv:        ["sub_command", "sub_sub_command"],
      expect_help: {{sub_sub_help_message}},
      expect_args_value: [] of String,
    },
    {
      argv:        ["sub_command", "sub_sub_command", "arg1"],
      expect_help: {{sub_sub_help_message}},
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["sub_command", "sub_sub_command", "arg1", "arg2"],
      expect_help: {{sub_sub_help_message}},
      expect_args_value: ["arg1", "arg2"],
    },
    {
      argv:        ["sub_command", "sub_sub_command", "arg1", "arg2", "arg3"],
      expect_help: {{sub_sub_help_message}},
      expect_args_value: ["arg1", "arg2", "arg3"],
    },
    {
      argv:              ["sub_command", "sub_sub_command", "--help", "-ignore-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["sub_command", "sub_sub_command", "-ignore-option", "--help"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-ignore-option\"",
      }
    },
    {
      argv:              ["sub_command", "sub_sub_command", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command", "sub_sub_command", "--missing-option"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--missing-option\"",
      }
    },
    {
      argv:              ["sub_command", "sub_sub_command", "-m", "arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command", "sub_sub_command", "arg1", "-m"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:              ["sub_command", "sub_sub_command", "-m", "-d"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
    },
    {
      argv:        ["sub_command", "sub_sub_command", "--help"],
      expect_help: {{sub_sub_help_message}},
    },
    {
      argv:        ["sub_command", "sub_sub_command", "--help", "ignore-arg"],
      expect_help: {{sub_sub_help_message}},
    },
    {
      argv:        ["sub_command", "sub_sub_command", "ignore-arg", "--help"],
      expect_help: {{sub_sub_help_message}},
    },
  ]
)
{% end %}
