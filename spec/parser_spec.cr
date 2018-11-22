require "./spec_helper"

describe Mare::Parser do
  it "parses an example" do
    source = fixture "example.mare"
    
    ast = Mare::Parser.parse(source)
    ast.should be_truthy
    next unless ast
    
    ll = [] of Mare::AST::A
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], ll],
      [:declare,
        [[:ident, "prop"], [:ident, "name"], [:ident, "String"]],
        [[:string, "World"]]
      ],
      [:declare,
        [[:ident, "fun"], [:ident, "greeting"], [:ident, "String"]],
        [[:relate,
          [:string, "Hello, "],
          [:op, "+"], [:prefix, [:op, "@"], [:ident, "name"]],
          [:op, "+"], [:string, "!"]
        ]]
      ],
      [:declare,
        [
          [:ident, "fun"],
          [:ident, "degreesF"],
          [:group, "(", [:relate, [:ident, "c"], [:op, " "], [:ident, "F64"]]],
          [:ident, "F64"]
        ],
        [[:relate,
          [:relate,
            [:ident, "c"],
            [:op, "*"], [:integer, 9],
            [:op, "/"], [:integer, 5]
          ],
          [:op, "+"], [:float, 32.0],
        ]]
      ],
      [:declare,
        [[:ident, "fun"], [:ident, "caller"]],
        [[:qualify,
          [:prefix, [:op, "@"], [:ident, "degreesF"]],
          [:group, "(",
            [:relate,
              [:integer, 10],
              [:op, "."], [:qualify,
                [:ident, "add"],
                [:group, "(", [:integer, 2]],
              ],
              [:op, "."], [:qualify,
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
    ast.should be_truthy
    next unless ast
    
    ll = [] of Mare::AST::A
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "describe"], [:ident, "operators"]], ll],
      [:declare, [[:ident, "demo"], [:ident, "all"]],
        [[:relate,
          [:ident, "x"],
          [:op, " "], [:relate,
            [:ident, "x"],
            [:op, "&&"], [:ident, "x"],
            [:op, "||"], [:relate,
              [:ident, "x"],
              [:op, "==="], [:ident, "x"],
              [:op, "=="], [:ident, "x"],
              [:op, "!=="], [:ident, "x"],
              [:op, "!="], [:ident, "x"],
              [:op, "=~"], [:relate,
                [:ident, "x"],
                [:op, ">="], [:ident, "x"],
                [:op, "<="], [:ident, "x"],
                [:op, "<"], [:ident, "x"],
                [:op, ">"], [:relate,
                  [:ident, "x"],
                  [:op, "<|>"], [:ident, "x"],
                  [:op, "<~>"], [:ident, "x"],
                  [:op, "<<<"], [:ident, "x"],
                  [:op, ">>>"], [:ident, "x"],
                  [:op, "<<~"], [:ident, "x"],
                  [:op, "~>>"], [:ident, "x"],
                  [:op, "<<"], [:ident, "x"],
                  [:op, ">>"], [:ident, "x"],
                  [:op, "<~"], [:ident, "x"],
                  [:op, "~>"], [:relate,
                    [:ident, "x"],
                    [:op, ".."], [:ident, "x"],
                    [:op, "<>"], [:relate,
                      [:ident, "x"],
                      [:op, "+"], [:ident, "x"],
                      [:op, "-"], [:relate,
                        [:ident, "x"],
                        [:op, "*"], [:ident, "x"],
                        [:op, "/"], [:ident, "x"],
                      ],
                    ],
                  ],
                ],
              ],
            ],
          ],
        ]],
      ],
      [:declare, [[:ident, "demo"], [:ident, "mixed"]],
        [[:relate,
          [:relate, [:ident, "a"], [:op, "!="], [:ident, "b"]],
          [:op, "&&"], [:relate,
            [:ident, "c"],
            [:op, ">"], [:relate,
              [:relate, [:ident, "d"], [:op, "/"], [:ident, "x"]],
              [:op, "+"], [:relate, [:ident, "e"], [:op, "/"], [:ident, "y"]],
            ],
          ],
          [:op, "||"], [:relate,
            [:relate, [:ident, "i"], [:op, ".."], [:ident, "j"]],
            [:op, ">"], [:relate, [:ident, "k"], [:op, "<<"], [:ident, "l"]],
          ],
        ]],
      ],
    ]
  end
end
