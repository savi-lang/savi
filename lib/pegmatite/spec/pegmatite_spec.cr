require "./spec_helper"

describe Pegmatite do
  it "tokenizes basic JSON and builds a tree of JSON nodes" do
    source = <<-JSON
    {
      "hello": "world",
      "from": {
        "name": "Pegmatite",
        "version": [0, 1, 0],
        "nifty": true,
        "overcomplicated": false,
        "worse-than": null,
        "problems": [],
        "utf8": ["Д", "Ⴃ", "𐀀"]
      }
    }
    JSON

    tokens = Pegmatite.tokenize(Fixtures::JSONGrammar, source)
    tokens.should eq [
      {:object, 0, 217},
      {:pair, 4, 20},
      {:string, 5, 10},  # "hello"
      {:string, 14, 19}, # "world"
      {:pair, 24, 215},
      {:string, 25, 29}, # "from"
      {:object, 32, 215},
      {:pair, 38, 57},
      {:string, 39, 43}, # "name"
      {:string, 47, 56}, # "Pegmatite"
      {:pair, 63, 83},
      {:string, 64, 71}, # "version"
      {:array, 74, 83},
      {:number, 75, 76}, # 0
      {:number, 78, 79}, # 1
      {:number, 81, 82}, # 0
      {:pair, 89, 102},
      {:string, 90, 95}, # "nifty"
      {:true, 98, 102},  # true
      {:pair, 108, 132},
      {:string, 109, 124}, # "overcomplicated"
      {:false, 127, 132},  # false
      {:pair, 138, 156},
      {:string, 139, 149}, # "worse-than"
      {:null, 152, 156},   # null
      {:pair, 162, 176},
      {:string, 163, 171}, # "problems"
      {:array, 174, 176},  # []
      {:pair, 182, 211},
      {:string, 183, 187}, # "utf8"
      {:array, 190, 211},
      {:string, 192, 194}, # (a string containing a 2-byte UTF-8 codepoint)
      {:string, 198, 201}, # (a string containing a 3-byte UTF-8 codepoint)
      {:string, 205, 209}, # (a string containing a 4-byte UTF-8 codepoint)
    ]

    result = Fixtures::JSONBuilder.build(tokens, source)
    result.should eq JSON::Any.new({
      "hello" => JSON::Any.new("world"),
      "from"  => JSON::Any.new({
        "name"    => JSON::Any.new("Pegmatite"),
        "version" => JSON::Any.new([
          JSON::Any.new(0_i64),
          JSON::Any.new(1_i64),
          JSON::Any.new(0_i64),
        ]),
        "nifty"           => JSON::Any.new(true),
        "overcomplicated" => JSON::Any.new(false),
        "worse-than"      => JSON::Any.new(nil),
        "problems"        => JSON::Any.new([] of JSON::Any),
        "utf8"            => JSON::Any.new(
          [JSON::Any.new("Д"), JSON::Any.new("Ⴃ"), JSON::Any.new("𐀀")]
        ),
      } of String => JSON::Any),
    } of String => JSON::Any)
  end

  it "traces the parsing process" do
    source = <<-JSON
    ["hello"]
    JSON

    io = IO::Memory.new
    Pegmatite.tokenize(Fixtures::JSONGrammar, source, 0, io)

    io.to_s
      .ends_with?("0 ~~~ then_eof - {9, [{:array, 0, 9}, {:string, 2, 7}]}\n")
      .should eq true
  end

  it "raises useful parse errors" do
    source = <<-JSON
    {
      "hello": !
    }
    JSON

    expected = <<-ERROR
    unexpected token at byte offset 13:
      "hello": !
               ^
    ERROR

    expect_raises Pegmatite::Pattern::MatchError, expected do
      Pegmatite.tokenize(Fixtures::JSONGrammar, source)
    end
  end

  it "correctly raises a parse error pointing to a newline" do
    source = <<-JSON
    {
      "hello": 93.
    }
    JSON

    expected = <<-ERROR
    unexpected token at byte offset 16:
      "hello": 93.
                  ^
    ERROR

    expect_raises Pegmatite::Pattern::MatchError, expected do
      Pegmatite.tokenize(Fixtures::JSONGrammar, source)
    end
  end

  it "correctly raises a parse error pointing to the end of the source" do
    source = "{\"hello\": 93."

    expected = <<-ERROR
    unexpected token at byte offset 13:
    {"hello": 93.
                 ^
    ERROR

    expect_raises Pegmatite::Pattern::MatchError, expected do
      Pegmatite.tokenize(Fixtures::JSONGrammar, source)
    end
  end

  it "correctly raises a parse error pointing to the beginning of the source" do
    source = ""

    expected = <<-ERROR
    unexpected token at byte offset 0:

    ^
    ERROR

    expect_raises Pegmatite::Pattern::MatchError, expected do
      Pegmatite.tokenize(Fixtures::JSONGrammar, source)
    end
  end

  it "correctly raises a parse error for an unterminated string literal" do
    source = "{\"hello\": \"uh oh"

    expected = <<-ERROR
    unexpected token at byte offset 16:
    {"hello": "uh oh
                    ^
    ERROR

    expect_raises Pegmatite::Pattern::MatchError, expected do
      Pegmatite.tokenize(Fixtures::JSONGrammar, source)
    end
  end

  describe Pegmatite::Pattern::MatchError do
    it "provides the offset of where the parse error ocurred" do
      source = "{\"hello\": \"uh oh"

      begin
        Pegmatite.tokenize(Fixtures::JSONGrammar, source)
      rescue err : Pegmatite::Pattern::MatchError
        err.offset.should eq(16)
      end
    end
  end
end
