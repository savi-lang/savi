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
      ]
    ]
  end
end
