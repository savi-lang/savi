require "./spec_helper"

describe Mare::Parser do
  it "parses an example" do
    source = fixture "example.mare"
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare,
        [[:ident, "prop"], [:ident, "name"], [:ident, "String"]],
        [:group, ":", [:string, "World"]]
      ],
      [:declare, ["Return a friendly greeting string for this instance."],
        [[:ident, "fun"], [:ident, "greeting"], [:ident, "String"]],
        [:group, ":", [:relate,
          [:relate,
            [:string, "Hello, "],
            [:op, "+"],
            [:ident, "@name"],
          ],
          [:op, "+"],
          [:string, "!"],
        ]]
      ],
      [:declare,
        [
          [:ident, "fun"],
          [:ident, "degreesF"],
          [:group, "(", [:group, " ", [:ident, "c"], [:ident, "F64"]]],
          [:ident, "F64"]
        ],
        [:group, ":", [:relate,
          [:relate,
            [:relate, [:ident, "c"], [:op, "*"], [:integer, 9]],
            [:op, "/"],
            [:integer, 5],
          ],
          [:op, "+"], [:float, 32.0],
        ]]
      ],
      [:declare,
        [[:ident, "fun"], [:ident, "caller"]],
        [:group, ":", [:qualify,
          [:ident, "@degreesF"],
          [:group, "(",
            [:relate,
              [:relate, [:integer, 10], [:op, "."], [:qualify,
                [:ident, "add"],
                [:group, "(", [:integer, 2]],
              ]],
              [:op, "."],
              [:qualify,
                [:ident, "sub"],
                [:group, "(", [:integer, 1]],
              ],
            ],
          ],
        ]]
      ],
    ]
  end
  
  it "parses operators" do
    source = fixture "operators.mare"
    
    ast = Mare::Parser.parse(source)
    
    # Can't use array literals here because Crystal is too slow to compile them.
    # See https://github.com/crystal-lang/crystal/issues/5792
    ast.to_a.pretty_inspect(74).should eq <<-AST
    [:doc,
     [:declare, [[:ident, "describe"], [:ident, "operators"]], [:group, ":"]],
     [:declare,
      [[:ident, "demo"], [:ident, "all"]],
      [:group,
       ":",
       [:relate,
        [:ident, "y"],
        [:op, "="],
        [:relate,
         [:relate, [:ident, "x"], [:op, "&&"], [:ident, "x"]],
         [:op, "||"],
         [:relate,
          [:relate,
           [:relate,
            [:relate,
             [:relate, [:ident, "x"], [:op, "==="], [:ident, "x"]],
             [:op, "=="],
             [:ident, "x"]],
            [:op, "!=="],
            [:ident, "x"]],
           [:op, "!="],
           [:ident, "x"]],
          [:op, "=~"],
          [:relate,
           [:relate,
            [:relate,
             [:relate, [:ident, "x"], [:op, ">="], [:ident, "x"]],
             [:op, "<="],
             [:ident, "x"]],
            [:op, "<"],
            [:ident, "x"]],
           [:op, ">"],
           [:relate,
            [:relate,
             [:relate,
              [:relate,
               [:relate,
                [:relate,
                 [:relate,
                  [:relate,
                   [:relate,
                    [:relate, [:ident, "x"], [:op, "<|>"], [:ident, "x"]],
                    [:op, "<~>"],
                    [:ident, "x"]],
                   [:op, "<<<"],
                   [:ident, "x"]],
                  [:op, ">>>"],
                  [:ident, "x"]],
                 [:op, "<<~"],
                 [:ident, "x"]],
                [:op, "~>>"],
                [:ident, "x"]],
               [:op, "<<"],
               [:ident, "x"]],
              [:op, ">>"],
              [:ident, "x"]],
             [:op, "<~"],
             [:ident, "x"]],
            [:op, "~>"],
            [:relate,
             [:relate, [:ident, "x"], [:op, ".."], [:ident, "x"]],
             [:op, "<>"],
             [:relate,
              [:relate, [:ident, "x"], [:op, "+"], [:ident, "x"]],
              [:op, "-"],
              [:relate,
               [:relate, [:ident, "x"], [:op, "*"], [:ident, "x"]],
               [:op, "/"],
               [:group,
                " ",
                [:ident, "x"],
                [:relate,
                 [:ident, "x"],
                 [:op, "."],
                 [:ident, "y"]]]]]]]]]]]]],
     [:declare,
      [[:ident, "demo"], [:ident, "mixed"]],
      [:group,
       ":",
       [:relate,
        [:relate,
         [:relate, [:ident, "a"], [:op, "!="], [:ident, "b"]],
         [:op, "&&"],
         [:relate,
          [:ident, "c"],
          [:op, ">"],
          [:relate,
           [:relate, [:ident, "d"], [:op, "/"], [:ident, "x"]],
           [:op, "+"],
           [:relate, [:ident, "e"], [:op, "/"], [:ident, "y"]]]]],
        [:op, "||"],
        [:relate,
         [:relate, [:ident, "i"], [:op, ".."], [:ident, "j"]],
         [:op, ">"],
         [:relate, [:ident, "k"], [:op, "<<"], [:ident, "l"]]]]]],
     [:declare,
      [[:ident, "demo"], [:ident, "prefix"]],
      [:group, ":", [:prefix, [:op, "~"], [:ident, "x"]]]]]
    AST
  end

  it "complains when a character literal has too many characters in it" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x U64 = '..'
    SOURCE
    
    expected = <<-MSG
    This character literal has more than one character in it:
    from (example):3:
        x U64 = '..'
                 ^~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Parser.parse(source)
    end
  end
end
