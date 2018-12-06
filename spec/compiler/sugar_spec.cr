require "./spec_helper"

describe Mare::Compiler::Sugar do
  it "transforms an operator to a method call" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Example:
      fun plus:
        x + y
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "plus"]], [:group, ":",
        [:relate, [:ident, "x"], [:op, "+"], [:ident, "y"]],
      ]],
    ]
    
    ctx = Mare::Compiler.compile(ast, limit: Mare::Compiler::Sugar)
    
    func = ctx.program.find_func!("Example", "plus")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "x"],
        [:op, "."],
        [:qualify, [:ident, "+"], [:group, "(", [:ident, "y"]]]
      ],
    ]
  end
end
