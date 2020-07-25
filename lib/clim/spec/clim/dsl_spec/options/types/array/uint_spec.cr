require "../../../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          --array-uint8=VALUE              Option description. [type:Array(UInt8)]
                          --array-uint16=VALUE             Option description. [type:Array(UInt16)]
                          --array-uint32=VALUE             Option description. [type:Array(UInt32)]
                          --array-uint64=VALUE             Option description. [type:Array(UInt64)]
                          --array-uint8-default=VALUE      Option description. [type:Array(UInt8)] [default:[] of UInt8]
                          --array-uint16-default=VALUE     Option description. [type:Array(UInt16)] [default:[] of UInt16]
                          --array-uint32-default=VALUE     Option description. [type:Array(UInt32)] [default:[] of UInt32]
                          --array-uint64-default=VALUE     Option description. [type:Array(UInt64)] [default:[] of UInt64]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: OptionTypeSpec,
  spec_dsl_lines: [
    "option \"--array-uint8=VALUE\", type: Array(UInt8)",
    "option \"--array-uint16=VALUE\", type: Array(UInt16)",
    "option \"--array-uint32=VALUE\", type: Array(UInt32)",
    "option \"--array-uint64=VALUE\", type: Array(UInt64)",
    "option \"--array-uint8-default=VALUE\", type: Array(UInt8), default: [] of UInt8",
    "option \"--array-uint16-default=VALUE\", type: Array(UInt16), default: [] of UInt16",
    "option \"--array-uint32-default=VALUE\", type: Array(UInt32), default: [] of UInt32",
    "option \"--array-uint64-default=VALUE\", type: Array(UInt64), default: [] of UInt64",
  ],
  spec_desc: "option type spec,",
  spec_cases: [
    # ====================================================
    # Array(UInt8)
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(UInt8),
        "method" => "array_uint8",
        "expect_value" => [] of UInt8,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-uint8", "1", "--array-uint8", "2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(UInt8),
        "method" => "array_uint8",
        "expect_value" => [1_u8, 2_u8],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-uint8", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid UInt8: foo",
      }
    },

    # ====================================================
    # Array(UInt16)
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(UInt16),
        "method" => "array_uint16",
        "expect_value" => [] of UInt16,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-uint16", "1", "--array-uint16", "2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(UInt16),
        "method" => "array_uint16",
        "expect_value" => [1_u16, 2_u16],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-uint16", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid UInt16: foo",
      }
    },

    # ====================================================
    # Array(UInt32)
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(UInt32),
        "method" => "array_uint32",
        "expect_value" => [] of UInt32,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-uint32", "1", "--array-uint32", "2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(UInt32),
        "method" => "array_uint32",
        "expect_value" => [1_u32, 2_u32],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-uint32", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid UInt32: foo",
      }
    },

    # ====================================================
    # Array(UInt64)
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(UInt64),
        "method" => "array_uint64",
        "expect_value" => [] of UInt64,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--array-uint64", "1", "--array-uint64", "2"],
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => Array(UInt64),
        "method" => "array_uint64",
        "expect_value" => [1_u64, 2_u64],
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--array-uint64", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid UInt64: foo",
      }
    },
  ]
)
{% end %}
