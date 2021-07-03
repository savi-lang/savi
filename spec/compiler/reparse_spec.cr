describe Mare::Compiler::Reparse do
  it "transforms a chained qualifications into chained method calls" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun chained
        x.call(y).call(z)
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
      ]],
    ]

    ctx = Mare.compiler.compile([ast], Mare::Compiler::Context.new, :reparse)
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
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Mare.compiler.compile([source], :reparse)
    ctx.program.libraries.should eq ctx2.program.libraries
  end

  it "transforms an @-prefixed identifier into a method call of @" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun selfish
        @x
        @x(y)
        @x -> (z, w | True)
        @x(y) -> (True)
    SOURCE

    ast = Mare::Parser.parse(source)

    ast.to_a.should eq [:doc,
      [:declare, [[:ident, "class"], [:ident, "Example"]], [:group, ":"]],
      [:declare, [[:ident, "fun"], [:ident, "selfish"]], [:group, ":",
        [:ident, "@x"],
        [:qualify, [:ident, "@x"], [:group, "(", [:ident, "y"]]],
        [:relate,
          [:ident, "@x"],
          [:op, "->"],
          [:group, "|",
            [:group, "(", [:ident, "z"], [:ident, "w"]],
            [:group, "(", [:ident, "True"]],
          ],
        ],
        [:relate,
          [:qualify, [:ident, "@x"], [:group, "(", [:ident, "y"]]],
          [:op, "->"],
          [:group, "(", [:ident, "True"]],
        ],
      ]],
    ]

    ctx = Mare.compiler.compile([ast], Mare::Compiler::Context.new, :reparse)
    ctx.errors.should be_empty

    func = ctx.namespace.find_func!(ctx, source, "Example", "selfish")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:call, [:ident, "@"], [:ident, "x"]],
      [:call, [:ident, "@"], [:ident, "x"], [:group, "(", [:ident, "y"]]],
      [:call,
        [:ident, "@"],
        [:ident, "x"],
        nil,
        [:group, "(", [:ident, "z"], [:ident, "w"]],
        [:group, "(", [:ident, "True"]],
      ],
      [:call,
        [:ident, "@"],
        [:ident, "x"],
        [:group, "(", [:ident, "y"]],
        nil,
        [:group, "(", [:ident, "True"]],
      ],
    ]

    # Compiling again should yield an equivalent program tree:
    ctx2 = Mare.compiler.compile([source], :reparse)
    ctx.program.libraries.should eq ctx2.program.libraries
  end
end
