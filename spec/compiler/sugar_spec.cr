describe Mare::Compiler::Sugar do
  it "transforms a property assignment into a method call" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun prop_assign
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
    
    func = ctx.namespace.find_func!("Example", "prop_assign")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "x"],
        [:op, "."],
        [:qualify, [:ident, "y="], [:group, "(", [:ident, "z"]]],
      ],
    ]
  end
  
  it "transforms an operator into a method call" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun plus
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
    
    func = ctx.namespace.find_func!("Example", "plus")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "x"],
        [:op, "."],
        [:qualify, [:ident, "+"], [:group, "(", [:ident, "y"]]]
      ],
    ]
  end
  
  it "transforms a square brace qualification into a method call" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun square
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
    
    func = ctx.namespace.find_func!("Example", "square")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "x"],
        [:op, "."],
        [:qualify, [:ident, "[]"], [:group, "(", [:ident, "y"]]]
      ],
    ]
  end
  
  it "transforms a square brace qualified assignment into a method call" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun square
        x[y] = z
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "square"]], [:group, ":",
        [:relate,
          [:qualify, [:ident, "x"], [:group, "[", [:ident, "y"]]],
          [:op, "="],
          [:ident, "z"]
        ],
      ]],
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.namespace.find_func!("Example", "square")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "x"],
        [:op, "."],
        [:qualify, [:ident, "[]="], [:group, "(", [:ident, "y"], [:ident, "z"]]]
      ],
    ]
  end
  
  it "transforms an @-prefixed identifier into a method call of @" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun selfish
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
    
    func = ctx.namespace.find_func!("Example", "selfish")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate, [:ident, "@"], [:op, "."], [:ident, "x"]],
      [:relate,
        [:ident, "@"],
        [:op, "."],
        [:qualify, [:ident, "x"], [:group, "(", [:ident, "y"]]],
      ],
    ]
  end
  
  it "adds a '@' statement to the end of a constructor body" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :new
        x = 1
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "new"]], [:group, ":",
        [:relate, [:ident, "x"], [:op, "="], [:integer, 1_u64]]
      ]]
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.namespace.find_func!("Example", "new")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate, [:ident, "x"], [:op, "="], [:integer, 1_u64]],
      [:ident, "@"],
    ]
  end
  
  it "transforms non-identifier parameters into assignment expressions" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun param_assigns (@x, @y.z)
        @y.after
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "param_assigns"], [:group, "(",
        [:ident, "@x"],
        [:relate, [:ident, "@y"], [:op, "."], [:ident, "z"]]],
      ], [:group, ":",
        [:relate, [:ident, "@y"], [:op, "."], [:ident, "after"]],
      ]],
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.namespace.find_func!("Example", "param_assigns")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "@"],
        [:op, "."],
        [:qualify, [:ident, "x="], [:group, "(", [:ident, "ASSIGNPARAM.0"]]]
      ],
      [:relate,
        [:relate, [:ident, "@"], [:op, "."], [:ident, "y"]],
        [:op, "."],
        [:qualify, [:ident, "z="], [:group, "(", [:ident, "ASSIGNPARAM.1"]]]
      ],
      [:relate,
        [:relate, [:ident, "@"], [:op, "."], [:ident, "y"]],
        [:op, "."],
        [:ident, "after"]
      ],
    ]
  end
  
  it "transforms short-circuiting logical operators into choices" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun logical
        w && x || y && z
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "logical"]], [:group, ":",
        [:relate,
          [:relate,
            [:relate,
              [:ident, "w"],
              [:op, "&&"],
              [:ident, "x"],
            ],
            [:op, "||"],
            [:ident, "y"],
          ],
          [:op, "&&"],
          [:ident, "z"],
        ],
      ]],
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.namespace.find_func!("Example", "logical")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:choice,
        [
          [:choice,
            [
              [:choice,
                [[:ident, "w"], [:ident, "x"]],
                [[:ident, "True"], [:ident, "False"]],
              ],
              [:ident, "True"],
            ],
            [[:ident, "True"], [:ident, "y"]],
          ],
          [:ident, "z"],
        ],
        [[:ident, "True"], [:ident, "False"]],
      ],
    ]
  end
end
