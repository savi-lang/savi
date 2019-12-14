require "./spec_helper"

describe "Pegmatite dynamic matchers" do
  it "can be used to parse heredoc-like structures" do
    source = <<-SRC
    one = 1
    two = <<-TWO
      I am a heredoc
    TWO
    three = 3

    SRC

    tokens = Pegmatite.tokenize(Fixtures::HeredocGrammar, source)

    tokens.should eq [
      {:attribute, 0, 8},
        {:identifier, 0, 3},     # one
        {:number, 6, 7},         # 1
      {:attribute, 8, 42},
        {:identifier, 8, 11},    # two
        {:heredoc, 14, 41},
          {:identifier, 17, 20}, # TWO
          {:string, 21, 38},     # "  I am a heredoc\n"
          {:identifier, 38, 41}, # TWO
      {:attribute, 42, 52},
        {:identifier, 42, 47},   # three
        {:number, 50, 51}        # 3
    ]
  end
end
