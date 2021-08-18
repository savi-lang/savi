require "json"

module LSP::Data
  struct FormattingOptions
    include JSON::Serializable
    include JSON::Serializable::Unmapped

    # Size of a tab in spaces.
    @[JSON::Field(key: "tabSize")]
    property tab_size : Int64 = 2

    # Prefer spaces over tabs.
    @[JSON::Field(key: "insertSpaces")]
    property insert_spaces : Bool = true

    # Trim trailing whitespace on a line.
    @[JSON::Field(key: "trimTrailingWhitespace")]
    property trim_trailing_whitespace : Bool?

    # Insert a newline character at the end of the file if one does not exist.
    @[JSON::Field(key: "insertFinalNewline")]
    property insert_final_newline : Bool?

    # Trim all newlines after the final newline at the end of the file.
    @[JSON::Field(key: "trimFinalNewlines")]
    property trim_final_newlines : Bool?

    # Signature for further properties.
    # [key: string]: boolean | integer | string;
    def [](key : String)
      @json_unmapped[key].raw.as(Bool | Int64 | String)
    end
    def []?(key : String)
      @json_unmapped[key]?.try(&.raw.as(Bool | Int64 | String))
    end
    def []=(key : String, value : Bool | Int64 | String)
      @json_unmapped[key] = JSON::Any.new(value)
    end

    def initialize(
      @tab_size = 2_i64,
      @insert_spaces = true,
      @trim_trailing_whitespace = nil,
      @insert_final_newline = nil,
      @trim_final_newlines = nil,
      @json_unmapped = {} of String => JSON::Any
    )
    end
  end
end
