describe Mare::Compiler::Sugar do
  it "inserts a None return value where it was left out" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Example
      :fun return_none None
        "this isn't the return value"
      
      :be behave
        "this isn't the return value"
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "actor"], [:ident, "Example"]], [:group, ":"]],
      [:declare,
        [[:ident, "fun"], [:ident, "return_none"], [:ident, "None"]],
        [:group, ":", [:string, "this isn't the return value"]],
      ],
      [:declare, [[:ident, "be"], [:ident, "behave"]], [:group, ":",
        [:string, "this isn't the return value"],
      ]]
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.namespace.find_func!("Example", "return_none")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:string, "this isn't the return value"],
      [:ident, "None"],
    ]
    
    func = ctx.namespace.find_func!("Example", "behave")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:string, "this isn't the return value"],
      [:ident, "None"],
    ]
  end
  
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
  
  it "transforms property arithmetic-assignments into method calls" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun prop_assign
        x.y += z
        x.y -= z
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "prop_assign"]], [:group, ":",
        [:relate,
          [:relate, [:ident, "x"], [:op, "."], [:ident, "y"]],
          [:op, "+="],
          [:ident, "z"],
        ],
        [:relate,
          [:relate, [:ident, "x"], [:op, "."], [:ident, "y"]],
          [:op, "-="], [:ident, "z"],
        ],
      ]],
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.namespace.find_func!("Example", "prop_assign")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "x"],
        [:op, "."],
        [:qualify, [:ident, "y="], [:group, "(",
          [:relate,
            [:relate, [:ident, "x"], [:op, "."], [:ident, "y"]],
            [:op, "."],
            [:qualify, [:ident, "+"], [:group, "(", [:ident, "z"]]]
          ],
        ]],
      ],
      [:relate,
        [:ident, "x"],
        [:op, "."],
        [:qualify, [:ident, "y="], [:group, "(",
          [:relate,
            [:relate, [:ident, "x"], [:op, "."], [:ident, "y"]],
            [:op, "."],
            [:qualify, [:ident, "-"], [:group, "(", [:ident, "z"]]]
          ],
        ]],
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
  
  it "transforms an operator into a method call (in a loop condition)" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun countdown
        while (x > 0) (
          y
        )
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "countdown"]], [:group, ":",
        [:group, " ",
          [:ident, "while"],
          [:group, "(",
            [:relate, [:ident, "x"], [:op, ">"], [:integer, 0_u64]]
          ],
          [:group, "(", [:ident, "y"]],
        ],
      ]],
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.namespace.find_func!("Example", "countdown")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:group, "(", [:loop,
        [:group, "(", [:relate,
          [:ident, "x"],
          [:op, "."],
          [:qualify, [:ident, ">"], [:group, "(", [:integer, 0_u64]]]
        ]],
        [:group, "(", [:ident, "y"]],
        [:ident, "None"]
      ]]
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
  
  it "transforms a chained qualifications into chained method calls" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun chained
        x.call(y).call(z)
        x[y][z]
        x.call(y)[y].call(z)[z]
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "chained"]], [:group, ":",
        [:qualify,
          [:relate,
            [:qualify,
              [:relate, [:ident, "x"], [:op, "."], [:ident, "call"]],
              [:group, "(", [:ident, "y"]],
            ],
            [:op, "."],
            [:ident, "call"],
          ],
          [:group, "(", [:ident, "z"]],
        ],
        [:qualify,
          [:qualify, [:ident, "x"], [:group, "[", [:ident, "y"]]],
          [:group, "[", [:ident, "z"]]
        ],
        [:qualify,
          [:qualify,
            [:relate,
              [:qualify,
                [:qualify,
                  [:relate, [:ident, "x"], [:op, "."], [:ident, "call"]],
                  [:group, "(", [:ident, "y"]],
                ],
                [:group, "[", [:ident, "y"]],
              ],
              [:op, "."],
              [:ident, "call"],
            ],
            [:group, "(", [:ident, "z"]],
          ],
          [:group, "[", [:ident, "z"]],
        ],
      ]],
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.namespace.find_func!("Example", "chained")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:relate,
          [:ident, "x"],
          [:op, "."],
          [:qualify, [:ident, "call"], [:group, "(", [:ident, "y"]]],
        ],
        [:op, "."],
        [:qualify, [:ident, "call"], [:group, "(", [:ident, "z"]]],
      ],
      [:relate,
        [:relate,
          [:ident, "x"],
          [:op, "."],
          [:qualify, [:ident, "[]"], [:group, "(", [:ident, "y"]]],
        ],
        [:op, "."],
        [:qualify, [:ident, "[]"], [:group, "(", [:ident, "z"]]],
      ],
      [:relate,
        [:relate,
          [:relate,
            [:relate,
              [:ident, "x"],
              [:op, "."],
              [:qualify, [:ident, "call"], [:group, "(", [:ident, "y"]]],
            ],
            [:op, "."],
            [:qualify, [:ident, "[]"], [:group, "(", [:ident, "y"]]],
          ],
          [:op, "."],
          [:qualify, [:ident, "call"], [:group, "(", [:ident, "z"]]],
        ],
        [:op, "."],
        [:qualify, [:ident, "[]"], [:group, "(", [:ident, "z"]]],
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
        [:qualify, [:ident, "x="], [:group, "(",
          [:prefix, [:op, "--"], [:ident, "ASSIGNPARAM.1"]],
        ]]
      ],
      [:relate,
        [:relate, [:ident, "@"], [:op, "."], [:ident, "y"]],
        [:op, "."],
        [:qualify, [:ident, "z="], [:group, "(",
          [:prefix, [:op, "--"], [:ident, "ASSIGNPARAM.2"]],
        ]]
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
  
  # TODO: Can this be done as a "universal method" rather than sugar?
  it "transforms an `as!` call into a subtype check in a choice" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun type_cast
        x.y.as!(Y).z
    SOURCE
    
    ast = Mare::Parser.parse(source)
    
    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "type_cast"]], [:group, ":",
        [:relate,
          [:qualify,
            [:relate,
              [:relate, [:ident, "x"], [:op, "."], [:ident, "y"]],
              [:op, "."],
              [:ident, "as!"],
            ],
            [:group, "(", [:ident, "Y"]],
          ],
          [:op, "."],
          [:ident, "z"],
        ]
      ]]
    ]
    
    ctx = Mare::Compiler.compile([ast], :sugar)
    
    func = ctx.namespace.find_func!("Example", "type_cast")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:group, "(",
          [:relate,
            [:ident, "hygienic_local.1"],
            [:op, "="],
            [:relate, [:ident, "x"], [:op, "."], [:ident, "y"]]
          ],
          [:choice, [
            [:relate,
              [:ident, "hygienic_local.1"], [:op, "<:"], [:ident, "Y"]],
              [:ident, "hygienic_local.1"]
            ],
            [[:ident, "True"], [:ident, "error!"]]
          ]
        ],
        [:op, "."],
        [:ident, "z"]
      ]
    ]
  end
end
