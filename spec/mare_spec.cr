require "./spec_helper"

describe Mare do
  it "parses an example" do
    source = fixture "example.mare"
    
    ast = Mare::Parser.new.parse(source)
    ast.should be_truthy
    
    visitor = Mare::Visitor.new
    visitor.visit(ast)
    
    ll = [] of Mare::AST::A
    visitor.doc.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], ll],
      [:declare,
        [[:ident, "prop"], [:ident, "name"], [:ident, "String"]],
        [[:string, "World"]]
      ],
      [:declare,
        [[:ident, "fun"], [:ident, "greeting"], [:ident, "String"]],
        [[:relate,
          [:string, "Hello, "],
          [:op, "+"], [:ident, "name"],
          [:op, "+"], [:string, "!"]
        ]]
      ],
      [:declare,
        [[:ident, "fun"], [:ident, "degreesF"], [:ident, "F64"]],
        [[:relate,
          [:relate,
            [:ident, "c"],
            [:op, "*"], [:ident, "9"],
            [:op, "/"], [:ident, "5"]
          ],
          [:op, "+"], [:ident, "32"],
        ]],
      ],
    ]
  end
  
  it "parses operators" do
    source = fixture "operators.mare"
    
    ast = Mare::Parser.new.parse(source)
    ast.should be_truthy
    
    visitor = Mare::Visitor.new
    visitor.visit(ast)
    
    ll = [] of Mare::AST::A
    visitor.doc.to_a.should eq [:doc,
      [:declare, [[:ident, "describe"], [:ident, "operators"]], ll],
      [:declare, [[:ident, "demo"], [:ident, "all"]],
        [[:relate,
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
