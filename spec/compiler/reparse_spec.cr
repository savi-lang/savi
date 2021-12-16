describe Savi::Compiler::Reparse do
  it "transforms a chained qualifications into chained method calls" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :fun chained
        x.call(y).call(z)
    SOURCE

    ctx = Savi.compiler.test_compile([source], :reparse)
    ctx.errors.should be_empty

    ctx.root_docs.first.to_a.should eq [:doc,
      [:declare, [:ident, "class"], [:ident, "Example"],
        [:declare, [:ident, "fun"], [:ident, "chained"],
          [:group, ":",
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
          ],
        ],
      ],
    ]

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
    ctx2 = Savi.compiler.test_compile([source], :reparse)
    ctx.program.packages.should eq ctx2.program.packages
  end

  it "transforms an @-prefixed identifier into a method call of @" do
    source = Savi::Source.new_example <<-SOURCE
    :class Example
      :fun selfish
        @x
        @x(y)
        @x -> (z, w | True)
        @x(y) -> (True)
    SOURCE

    ctx = Savi.compiler.test_compile([source], :reparse)
    ctx.errors.should be_empty

    ctx.root_docs.first.to_a.should eq [:doc,
      [:declare, [:ident, "class"], [:ident, "Example"],
        [:declare, [:ident, "fun"], [:ident, "selfish"],
          [:group, ":",
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
          ],
        ],
      ],
    ]

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
    ctx2 = Savi.compiler.test_compile([source], :reparse)
    ctx.program.packages.should eq ctx2.program.packages
  end
end
