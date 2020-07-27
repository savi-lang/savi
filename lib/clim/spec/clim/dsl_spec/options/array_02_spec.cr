require "../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          -a ARG, --array=ARG              Array option description. [type:Array(String)] [default:["default value"]] [required]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: MainCommandWithArrayRequiredTrueAndDefaultExists,
  spec_dsl_lines: [
    "option \"-a ARG\", \"--array=ARG\", type: Array(String), desc: \"Array option description.\", required: true, default: [\"default value\"]",
  ],
  spec_desc: "main command with Array(String) option,",
  spec_cases: [
    {
      argv:        ["-a", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-aarray1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array=array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-a", "array1", "arg1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["arg1", "-a", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["-array"], # Unintended case.
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["rray"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-a=array1"], # Unintended case.
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["=array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              [] of String,
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Required options. \"-a ARG\"",
      }
    },
    {
      argv:              ["arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Required options. \"-a ARG\"",
      }
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
      argv:              ["-a"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"-a\"",
      }
    },
    {
      argv:              ["--array"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"--array\"",
      }
    },
    {
      argv:              ["arg1", "-a"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"-a\"",
      }
    },
    {
      argv:              ["arg1", "--array"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"--array\"",
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

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          -a ARG, --array=ARG              Array option description. [type:Array(String)] [required]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: MainCommandWithArrayRequiredTrueOnly,
  spec_dsl_lines: [
    "option \"-a ARG\", \"--array=ARG\", type: Array(String), desc: \"Array option description.\", required: true",
  ],
  spec_desc: "main command with Array(String) option,",
  spec_cases: [
    {
      argv:        ["-a", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-aarray1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array=array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-a", "array1", "arg1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["arg1", "-a", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["-array"], # Unintended case.
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["rray"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-a=array1"], # Unintended case.
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["=array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              [] of String,
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Required options. \"-a ARG\"",
      }
    },
    {
      argv:              ["arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Required options. \"-a ARG\"",
      }
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
      argv:              ["arg1"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Required options. \"-a ARG\"",
      }
    },
    {
      argv:              ["-a"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"-a\"",
      }
    },
    {
      argv:              ["--array"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"--array\"",
      }
    },
    {
      argv:              ["arg1", "-a"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"-a\"",
      }
    },
    {
      argv:              ["arg1", "--array"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"--array\"",
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

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          -a ARG, --array=ARG              Array option description. [type:Array(String)] [default:["default value"]]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: MainCommandWithArrayRequiredFalseAndDefaultExists,
  spec_dsl_lines: [
    "option \"-a ARG\", \"--array=ARG\", type: Array(String), desc: \"Array option description.\", required: false, default: [\"default value\"]",
  ],
  spec_desc: "main command with Array(String) option,",
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["default value"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["arg1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["default value"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["-a", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-aarray1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array=array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-a", "array1", "arg1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["arg1", "-a", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["-array"], # Unintended case.
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["rray"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-a=array1"], # Unintended case.
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["=array1"],
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
      argv:              ["-a"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"-a\"",
      }
    },
    {
      argv:              ["--array"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"--array\"",
      }
    },
    {
      argv:              ["arg1", "-a"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"-a\"",
      }
    },
    {
      argv:              ["arg1", "--array"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"--array\"",
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

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          -a ARG, --array=ARG              Array option description. [type:Array(String)]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: MainCommandWithArrayRequiredFalseOnly,
  spec_dsl_lines: [
    "option \"-a ARG\", \"--array=ARG\", type: Array(String), desc: \"Array option description.\", required: false",
  ],
  spec_desc: "main command with Array(String) option,",
  spec_cases: [
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => [] of String,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["arg1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => [] of String,
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["-a", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-aarray1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array=array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-a", "array1", "arg1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["arg1", "-a", "array1"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["array1"],
      },
      expect_args_value: ["arg1"],
    },
    {
      argv:        ["-array"], # Unintended case.
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["rray"],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-a=array1"], # Unintended case.
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(String),
        "method" => "array",
        "expect_value" => ["=array1"],
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
      argv:              ["-a"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"-a\"",
      }
    },
    {
      argv:              ["--array"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"--array\"",
      }
    },
    {
      argv:              ["arg1", "-a"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"-a\"",
      }
    },
    {
      argv:              ["arg1", "--array"],
      exception_message: {
        exception: Clim::ClimInvalidOptionException,
        message:   "Option that requires an argument. \"--array\"",
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
