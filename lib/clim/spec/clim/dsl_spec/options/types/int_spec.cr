require "../../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          -i=VALUE, --int8=VALUE           Option description. [type:Int8]
                          --int8-default=VALUE             Option description. [type:Int8] [default:1]
                          --int16=VALUE                    Option description. [type:Int16]
                          --int32=VALUE                    Option description. [type:Int32]
                          --int64=VALUE                    Option description. [type:Int64]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: OptionTypeSpec,
  spec_dsl_lines: [
    "option \"-i=VALUE\", \"--int8=VALUE\", type: Int8",
    "option \"--int8-default=VALUE\", type: Int8, default: 1_i8",
    "option \"--int16=VALUE\", type: Int16",
    "option \"--int32=VALUE\", type: Int32",
    "option \"--int64=VALUE\", type: Int64",
  ],
  spec_desc: "option type spec,",
  spec_cases: [
    # ====================================================
    # Int8
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Int8?,
        "method" => "int8",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["-i", "5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Int8?,
        "method" => "int8",
        "expect_value" => 5_i8,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["-i", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int8: foo",
      }
    },
    {
      argv:        ["--int8", "5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Int8?,
        "method" => "int8",
        "expect_value" => 5_i8,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--int8", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int8: foo",
      }
    },
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Int8,
        "method" => "int8_default",
        "expect_value" => 1_i8,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--int8-default", "5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Int8,
        "method" => "int8_default",
        "expect_value" => 5_i8,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--int8-default", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int8: foo",
      }
    },

    # ====================================================
    # Int16
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Int16?,
        "method" => "int16",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--int16", "5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Int16?,
        "method" => "int16",
        "expect_value" => 5_i16,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--int16", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int16: foo",
      }
    },

    # ====================================================
    # Int32
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Int32?,
        "method" => "int32",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--int32", "5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Int32?,
        "method" => "int32",
        "expect_value" => 5_i32,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--int32", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int32: foo",
      }
    },

    # ====================================================
    # Int64
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Int64?,
        "method" => "int64",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--int64", "5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Int64?,
        "method" => "int64",
        "expect_value" => 5_i64,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--int64", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int64: foo",
      }
    },
  ]
)
{% end %}
