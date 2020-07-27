require "../../../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          --array-int8=VALUE               Option description. [type:Array(Int8)]
                          --array-int16=VALUE              Option description. [type:Array(Int16)]
                          --array-int32=VALUE              Option description. [type:Array(Int32)]
                          --array-int64=VALUE              Option description. [type:Array(Int64)]
                          --array-int8-default=VALUE       Option description. [type:Array(Int8)] [default:[] of Int8]
                          --array-int8-default-value=VALUE Option description. [type:Array(Int8)] [default:[1, 2, 3]]
                          --array-int16-default=VALUE      Option description. [type:Array(Int16)] [default:[] of Int16]
                          --array-int32-default=VALUE      Option description. [type:Array(Int32)] [default:[] of Int32]
                          --array-int64-default=VALUE      Option description. [type:Array(Int64)] [default:[] of Int64]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: OptionTypeSpec,
  spec_dsl_lines: [
    "option \"--array-int8=VALUE\", type: Array(Int8)",
    "option \"--array-int16=VALUE\", type: Array(Int16)",
    "option \"--array-int32=VALUE\", type: Array(Int32)",
    "option \"--array-int64=VALUE\", type: Array(Int64)",
    "option \"--array-int8-default=VALUE\", type: Array(Int8), default: [] of Int8",
    "option \"--array-int8-default-value=VALUE\", type: Array(Int8), default: [1_i8,2_i8,3_i8]",
    "option \"--array-int16-default=VALUE\", type: Array(Int16), default: [] of Int16",
    "option \"--array-int32-default=VALUE\", type: Array(Int32), default: [] of Int32",
    "option \"--array-int64-default=VALUE\", type: Array(Int64), default: [] of Int64",
  ],
  spec_desc: "option type spec,",
  spec_cases: [
    # ====================================================
    # Array(Int8)
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int8),
        "method" => "array_int8",
        "expect_value" => [] of Int8,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-int8", "1", "--array-int8", "2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int8),
        "method" => "array_int8",
        "expect_value" => [1_i8, 2_i8],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-int8", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int8: foo",
      }
    },
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int8),
        "method" => "array_int8_default",
        "expect_value" => [] of Int8,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-int8-default", "1", "--array-int8-default", "2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int8),
        "method" => "array_int8_default",
        "expect_value" => [1_i8, 2_i8],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-int8-default", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int8: foo",
      }
    },
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int8),
        "method" => "array_int8_default_value",
        "expect_value" => [1_i8, 2_i8, 3_i8],
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-int8-default-value", "8", "--array-int8-default-value", "9"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int8),
        "method" => "array_int8_default_value",
        "expect_value" => [8_i8, 9_i8],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-int8-default-value", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int8: foo",
      }
    },

    # ====================================================
    # Array(Int16)
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int16),
        "method" => "array_int16",
        "expect_value" => [] of Int16,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-int16", "1", "--array-int16", "2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int16),
        "method" => "array_int16",
        "expect_value" => [1_i16, 2_i16],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-int16", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int16: foo",
      }
    },

    # ====================================================
    # Array(Int32)
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int32),
        "method" => "array_int32",
        "expect_value" => [] of Int32,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-int32", "1", "--array-int32", "2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int32),
        "method" => "array_int32",
        "expect_value" => [1_i32, 2_i32],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-int32", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int32: foo",
      }
    },

    # ====================================================
    # Array(Int64)
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int64),
        "method" => "array_int64",
        "expect_value" => [] of Int64,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-int64", "1", "--array-int64", "2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(Int64),
        "method" => "array_int64",
        "expect_value" => [1_i64, 2_i64],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-int64", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid Int64: foo",
      }
    },
  ]
)
{% end %}
