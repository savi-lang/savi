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
        "problems": []
      }
    }
    JSON
    
    tokens = Pegmatite.tokenize(Fixtures::JSONGrammar, source)
    tokens.should eq [
      {:object, 0, 182},
        {:pair, 4, 20},
          {:string, 5, 10}, # "hello"
          {:string, 14, 19}, # "world"
        {:pair, 24, 180},
          {:string, 25, 29}, # "from"
          {:object, 32, 180},
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
          {:true, 98, 102}, # true
        {:pair, 108, 132},
          {:string, 109, 124}, # "overcomplicated"
          {:false, 127, 132}, # false
        {:pair, 138, 156},
          {:string, 139, 149}, # "worse-than"
          {:null, 152, 156}, # null
        {:pair, 162, 176},
          {:string, 163, 171}, # "problems"
          {:array, 174, 176}, # []
    ]
    
    result = Fixtures::JSONBuilder.build(tokens, source)
    result.should eq JSON::Any.new({
      "hello" => JSON::Any.new("world"),
      "from" => JSON::Any.new({
        "name" => JSON::Any.new("Pegmatite"),
        "version" => JSON::Any.new([
          JSON::Any.new(0_i64),
          JSON::Any.new(1_i64),
          JSON::Any.new(0_i64),
        ]),
        "nifty" => JSON::Any.new(true),
        "overcomplicated" => JSON::Any.new(false),
        "worse-than" => JSON::Any.new(nil),
        "problems" => JSON::Any.new([] of JSON::Any),
      } of String => JSON::Any)
    } of String => JSON::Any)
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
    source = <<-JSON
    {
      "hello": 93.
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
end
