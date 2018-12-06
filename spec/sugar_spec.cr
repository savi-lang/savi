require "./spec_helper"

describe Mare::Compiler::Sugar do
  it "transforms an operator to a method call" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Example:
      fun plus:
        x + y
    SOURCE
    
    ast = Mare::Parser.parse(source)
    ast.should be_truthy
    next unless ast
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "plus"]], [:group, ":",
        [:relate, [:ident, "x"], [:op, "+"], [:ident, "y"]],
      ]],
    ]
    
    ast.accept Mare::Compiler::Sugar.new
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "plus"]], [:group, ":",
        [:relate,
          [:ident, "x"],
          [:op, "."],
          [:qualify, [:ident, "+"], [:group, "(", [:ident, "y"]]]
        ],
      ]],
    ]
  end
end
