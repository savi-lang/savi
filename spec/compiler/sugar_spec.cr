describe Savi::Compiler::Sugar do
  it "inserts a None return value where it was left out" do
    source = Savi::Source.new_example <<-SOURCE
    :actor Example
      :fun return_none None
        "this isn't the return value"

      :be behave
        "this isn't the return value"
    SOURCE

    ast = Savi::Parser.parse(source)

    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "actor"], [:ident, "Example"]], [:group, ":"]],
      [:declare,
        [[:ident, "fun"], [:ident, "return_none"], [:ident, "None"]],
        [:group, ":", [:string, "this isn't the return value", nil]],
      ],
      [:declare, [[:ident, "be"], [:ident, "behave"]], [:group, ":",
        [:string, "this isn't the return value", nil],
      ]]
    ]

    ctx = Savi.compiler.compile([ast], Savi::Compiler::Context.new, :sugar)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "return_none")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:string, "this isn't the return value", nil],
      [:ident, "None"],
    ]

    func = ctx.namespace.find_func!(ctx, source, "Example", "behave")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:string, "this isn't the return value", nil],
      [:ident, "None"],
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Savi.compiler.compile([source], :sugar)
    ctx.program.libraries.should eq ctx2.program.libraries
  end

  it "transforms a property assignment into a method call" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :fun prop_assign
        x.y = z
        x.y! = z
    SOURCE

    ast = Savi::Parser.parse(source)

    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "prop_assign"]], [:group, ":",
        [:relate,
          [:relate, [:ident, "x"], [:op, "."], [:ident, "y"]],
          [:op, "="],
          [:ident, "z"],
        ],
        [:relate,
          [:relate, [:ident, "x"], [:op, "."], [:ident, "y!"]],
          [:op, "="],
          [:ident, "z"],
        ],
      ]],
    ]

    ctx = Savi.compiler.compile([ast], Savi::Compiler::Context.new, :sugar)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "prop_assign")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:call,
        [:ident, "x"],
        [:ident, "y="],
        [:group, "(", [:ident, "z"]],
      ],
      [:call,
        [:ident, "x"],
        [:ident, "y=!"],
        [:group, "(", [:ident, "z"]],
      ],
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Savi.compiler.compile([source], :sugar)
    ctx.program.libraries.should eq ctx2.program.libraries
  end

  it "transforms property arithmetic-assignments into method calls" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :fun prop_assign
        x.y += z
        x.y -= z
    SOURCE

    ast = Savi::Parser.parse(source)

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

    ctx = Savi.compiler.compile([ast], Savi::Compiler::Context.new, :sugar)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "prop_assign")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:call,
        [:ident, "x"],
        [:ident, "y="],
        [:group, "(",
          [:call,
            [:call, [:ident, "x"], [:ident, "y"]],
            [:ident, "+"],
            [:group, "(", [:ident, "z"]],
          ],
        ],
      ],
      [:call,
        [:ident, "x"],
        [:ident, "y="],
        [:group, "(",
          [:call,
            [:call, [:ident, "x"], [:ident, "y"]],
            [:ident, "-"],
            [:group, "(", [:ident, "z"]],
          ],
        ],
      ],
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Savi.compiler.compile([source], :sugar)
    ctx.program.libraries.should eq ctx2.program.libraries
  end

  it "transforms an operator into a method call" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :fun plus
        x + y
    SOURCE

    ast = Savi::Parser.parse(source)

    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "plus"]], [:group, ":",
        [:relate, [:ident, "x"], [:op, "+"], [:ident, "y"]],
      ]],
    ]

    ctx = Savi.compiler.compile([ast], Savi::Compiler::Context.new, :sugar)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "plus")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:call,
        [:ident, "x"],
        [:ident, "+"],
        [:group, "(", [:ident, "y"]],
      ],
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Savi.compiler.compile([source], :sugar)
    ctx.program.libraries.should eq ctx2.program.libraries
  end

  it "transforms an operator into a method call (in a loop condition)" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :fun countdown
        while (x > 0) (
          y
        )
    SOURCE

    ast = Savi::Parser.parse(source)

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

    ctx = Savi.compiler.compile([ast], Savi::Compiler::Context.new, :sugar)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "countdown")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:group, "(", [:loop,
        [:group, "(", [:call,
          [:ident, "x"],
          [:ident, ">"],
          [:group, "(", [:integer, 0_u64]],
        ]],
        [:group, "(", [:ident, "y"]],
        [:group, "(", [:call,
          [:ident, "x"],
          [:ident, ">"],
          [:group, "(", [:integer, 0_u64]],
        ]],
        [:ident, "None"]
      ]]
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Savi.compiler.compile([source], :sugar)
    ctx.program.libraries.should eq ctx2.program.libraries
  end

  it "transforms a square brace qualification into a method call" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :fun square
        x[y]
    SOURCE

    ast = Savi::Parser.parse(source)

    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "square"]], [:group, ":",
        [:qualify, [:ident, "x"], [:group, "[", [:ident, "y"]]],
      ]],
    ]

    ctx = Savi.compiler.compile([ast], Savi::Compiler::Context.new, :sugar)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "square")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:call,
        [:ident, "x"],
        [:ident, "[]"], [:group, "(", [:ident, "y"]]
      ],
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Savi.compiler.compile([source], :sugar)
    ctx.program.libraries.should eq ctx2.program.libraries
  end

  it "transforms a chained qualifications into chained method calls" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :fun chained
        x.call(y).call(z)
        x[y][z]
        x.call(y)[y].call(z)[z]
    SOURCE

    ast = Savi::Parser.parse(source)

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

    ctx = Savi.compiler.compile([ast], Savi::Compiler::Context.new, :sugar)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "chained")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:call,
        [:call,
          [:ident, "x"],
          [:ident, "call"],
          [:group, "(", [:ident, "y"]],
        ],
        [:ident, "call"],
        [:group, "(", [:ident, "z"]],
      ],
      [:call,
        [:call,
          [:ident, "x"],
          [:ident, "[]"],
          [:group, "(", [:ident, "y"]],
        ],
        [:ident, "[]"],
        [:group, "(", [:ident, "z"]],
      ],
      [:call,
        [:call,
          [:call,
            [:call,
              [:ident, "x"],
              [:ident, "call"],
              [:group, "(", [:ident, "y"]],
            ],
            [:ident, "[]"],
            [:group, "(", [:ident, "y"]],
          ],
          [:ident, "call"],
          [:group, "(", [:ident, "z"]],
        ],
        [:ident, "[]"],
        [:group, "(", [:ident, "z"]],
      ],
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Savi.compiler.compile([source], :sugar)
    ctx.program.libraries.should eq ctx2.program.libraries
  end

  it "transforms a square brace qualified assignment into a method call" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :fun square
        x[y] = z
    SOURCE

    ast = Savi::Parser.parse(source)

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

    ctx = Savi.compiler.compile([ast], Savi::Compiler::Context.new, :sugar)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "square")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:call,
        [:ident, "x"],
        [:ident, "[]="],
        [:group, "(", [:ident, "y"], [:ident, "z"]],
      ],
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Savi.compiler.compile([source], :sugar)
    ctx.program.libraries.should eq ctx2.program.libraries
  end

  it "adds a '@' statement to the end of a constructor body" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :new
        x = 1
    SOURCE

    ast = Savi::Parser.parse(source)

    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "new"]], [:group, ":",
        [:relate, [:ident, "x"], [:op, "="], [:integer, 1_u64]]
      ]]
    ]

    ctx = Savi.compiler.compile([ast], Savi::Compiler::Context.new, :sugar)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "new")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate, [:ident, "x"], [:op, "="], [:integer, 1_u64]],
      [:ident, "@"],
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Savi.compiler.compile([source], :sugar)
    ctx.program.libraries.should eq ctx2.program.libraries
  end

  it "transforms non-identifier parameters into assignment expressions" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :fun param_assigns(@x, @y.z)
        @y.after
    SOURCE

    ast = Savi::Parser.parse(source)

    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:qualify, [:ident, "param_assigns"],
          [:group, "(",
            [:ident, "@x"],
            [:relate, [:ident, "@y"], [:op, "."], [:ident, "z"]]
          ],
        ]],
        [:group, ":",
        [:relate, [:ident, "@y"], [:op, "."], [:ident, "after"]],
      ]],
    ]

    ctx = Savi.compiler.compile([ast], Savi::Compiler::Context.new, :sugar)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "param_assigns")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:call,
        [:ident, "@"],
        [:ident, "x="],
        [:group, "(",
          [:prefix, [:op, "--"], [:ident, "ASSIGNPARAM.1"]],
        ],
      ],
      [:call,
        [:call, [:ident, "@"], [:ident, "y"]],
        [:ident, "z="],
        [:group, "(",
          [:prefix, [:op, "--"], [:ident, "ASSIGNPARAM.2"]],
        ],
      ],
      [:call,
        [:call, [:ident, "@"], [:ident, "y"]],
        [:ident, "after"]
      ],
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Savi.compiler.compile([source], :sugar)
    ctx.program.libraries.should eq ctx2.program.libraries
  end

  it "transforms short-circuiting logical operators and negations" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :fun logical
        w && x || y && !z
    SOURCE

    ast = Savi::Parser.parse(source)

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
          [:prefix, [:op, "!"], [:ident, "z"]],
        ],
      ]],
    ]

    ctx = Savi.compiler.compile([ast], Savi::Compiler::Context.new, :sugar)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "logical")
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
          [:call,
            [:ident, "False"],
            [:ident, "=="],
            [:group, "(", [:ident, "z"]],
          ],
        ],
        [[:ident, "True"], [:ident, "False"]],
      ],
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Savi.compiler.compile([source], :sugar)
    ctx.program.libraries.should eq ctx2.program.libraries
  end
end
