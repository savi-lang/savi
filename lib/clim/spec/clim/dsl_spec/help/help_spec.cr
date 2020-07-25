require "../../dsl_spec"

macro spec_for_help(spec_class_name, spec_desc, spec_cases, spec_dsl_lines = [] of StringLiteral, spec_class_define_lines = [] of StringLiteral, spec_sub_command_lines = [] of StringLiteral)
  {% for spec_case, index in spec_cases %}
    {% class_name = (spec_class_name.stringify + index.stringify).id %}

    # define dsl
    class {{class_name}} < Clim
      expand_lines({{spec_class_define_lines}})
      main do
        expand_lines({{spec_dsl_lines}})
        run do |opts, args|
          assert_opts_and_args({{spec_case}})
        end
        expand_lines({{spec_sub_command_lines}})
      end
    end

    # spec
    describe {{spec_desc}} do
      describe "if dsl is [" + {{spec_dsl_lines.join(", ")}} + "]," do
        describe "if argv is " + {{spec_case["argv"].stringify}} + "," do
          it_blocks({{class_name}}, {{spec_case}})
        end
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

                          -h, --help                       Show this help.


                      HELP_MESSAGE
%}

spec_for_help(
  spec_class_name: HelpSpec,
  spec_dsl_lines: [
    "help short: \"-h\"",
  ],
  spec_desc: "main command,",
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
    argv:              ["-m"],
    exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
  },
  {
    argv:              ["--missing-option"],
    exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--missing-option\"",
      }
  },
  {
    argv:              ["-m", "arg1"],
    exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
  },
  {
    argv:              ["arg1", "-m"],
    exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
  },
  {
    argv:              ["-m", "-d"],
    exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
  },
  {
    argv:        ["-h"],
    expect_help: {{main_help_message}},
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

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          -a, --help                       Show this help.


                      HELP_MESSAGE
%}

spec_for_help(
  spec_class_name: HelpSpecOtherShortOption,
  spec_dsl_lines: [
    "help short: \"-a\"",
  ],
  spec_desc: "main command,",
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
    argv:              ["-m"],
    exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
  },
  {
    argv:              ["--missing-option"],
    exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"--missing-option\"",
      }
  },
  {
    argv:              ["-m", "arg1"],
    exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
  },
  {
    argv:              ["arg1", "-m"],
    exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
  },
  {
    argv:              ["-m", "-d"],
    exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Undefined option. \"-m\"",
      }
  },
  {
    argv:        ["-a"],
    expect_help: {{main_help_message}},
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
