require "../../../dsl_spec"

{% begin %}
{%
  main_help_message = <<-HELP_MESSAGE

                        Command Line Interface Tool.

                        Usage:

                          main_of_clim_library [options] [arguments]

                        Options:

                          --uint8=VALUE                    Option description. [type:UInt8]
                          --uint16=VALUE                   Option description. [type:UInt16]
                          --uint32=VALUE                   Option description. [type:UInt32]
                          --uint64=VALUE                   Option description. [type:UInt64]
                          --help                           Show this help.


                      HELP_MESSAGE
%}

spec(
  spec_class_name: OptionTypeSpec,
  spec_dsl_lines: [
    "option \"--uint8=VALUE\", type: UInt8",
    "option \"--uint16=VALUE\", type: UInt16",
    "option \"--uint32=VALUE\", type: UInt32",
    "option \"--uint64=VALUE\", type: UInt64",
  ],
  spec_desc: "option type spec,",
  spec_cases: [
    # ====================================================
    # UInt8
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => UInt8?,
        "method" => "uint8",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--uint8", "5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => UInt8?,
        "method" => "uint8",
        "expect_value" => 5_u8,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--uint8", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid UInt8: foo",
      }
    },

    # ====================================================
    # UInt16
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => UInt16?,
        "method" => "uint16",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--uint16", "5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => UInt16?,
        "method" => "uint16",
        "expect_value" => 5_u16,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--uint16", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid UInt16: foo",
      }
    },

    # ====================================================
    # UInt32
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => UInt32?,
        "method" => "uint32",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--uint32", "5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => UInt32?,
        "method" => "uint32",
        "expect_value" => 5_u32,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--uint32", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid UInt32: foo",
      }
    },

    # ====================================================
    # UInt64
    # ====================================================
    {
      argv:        [] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => UInt64?,
        "method" => "uint64",
        "expect_value" => nil,
      },
      expect_args_value: [] of String,
    },
    {
      argv:        ["--uint64", "5"] of String,
      expect_help: {{main_help_message}},
      expect_opts: {
        "type" => UInt64?,
        "method" => "uint64",
        "expect_value" => 5_u64,
      },
      expect_args_value: [] of String,
    },
    {
      argv:              ["--uint64", "foo"],
      exception_message: {
        exception: Clim::ClimInvalidTypeCastException,
        message:   "Invalid UInt64: foo",
      }
    },
  ]
)
{% end %}
