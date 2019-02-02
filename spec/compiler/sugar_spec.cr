describe Mare::Compiler::Sugar do
  it "transforms a property assignment into a method call" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Example:
      fun prop_assign:
        x.y = z
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "prop_assign"]], [:group, ":",
        [:relate,
          [:relate, [:ident, "x"], [:op, "."], [:ident, "y"]],
          [:op, "="],
          [:ident, "z"],
        ],
      ]],
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.program.find_func!("Example", "prop_assign")
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
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.program.find_func!("Example", "plus")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "x"],
        [:op, "."],
        [:qualify, [:ident, "+"], [:group, "(", [:ident, "y"]]]
      ],
    ]
  end
  
  it "transforms a square brace qualification into a method call" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Example:
      fun square:
        x[y]
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "square"]], [:group, ":",
        [:qualify, [:ident, "x"], [:group, "[", [:ident, "y"]]],
      ]],
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.program.find_func!("Example", "square")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "x"],
        [:op, "."],
        [:qualify, [:ident, "[]"], [:group, "(", [:ident, "y"]]]
      ],
    ]
  end
  
  it "transforms an @-prefixed identifier into a method call of @" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Example:
      fun selfish:
        @x
        @x(y)
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "selfish"]], [:group, ":",
        [:ident, "@x"],
        [:qualify, [:ident, "@x"], [:group, "(", [:ident, "y"]]],
      ]],
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.program.find_func!("Example", "selfish")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate, [:ident, "@"], [:op, "."], [:ident, "x"]],
      [:relate,
        [:ident, "@"],
        [:op, "."],
        [:qualify, [:ident, "x"], [:group, "(", [:ident, "y"]]],
      ],
    ]
  end
end
