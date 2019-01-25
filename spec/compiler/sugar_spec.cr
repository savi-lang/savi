describe Mare::Compiler::Sugar do
  it "transforms a property assignment into a method call" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Example:
      fun plus:
        x.y = z
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "plus"]], [:group, ":",
        [:relate,
          [:relate, [:ident, "x"], [:op, "."], [:ident, "y"]],
          [:op, "="],
          [:ident, "z"],
        ],
      ]],
    ]
    
    ctx = Mare::Compiler.compile(ast, limit: Mare::Compiler::Sugar)
    
    func = ctx.program.find_func!("Example", "plus")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "x"],
        [:op, "."],
        [:qualify, [:ident, "y="], [:group, "(", [:ident, "z"]]],
      ],
    ]
  end
  
  it "transforms an operator into a method call" do
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
