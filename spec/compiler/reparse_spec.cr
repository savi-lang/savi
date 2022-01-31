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

  it "transforms an nested type identifier into its single-identifier form" do
    source = Savi::Source.new_example <<-SOURCE
    :trait Mumeric.Convertible // TODO: Remove when in standard library
    :class Example(T Mumeric.Convertible)
      :fun example(value Mumeric.Convertible) Mumeric.Convertible
        Mumeric.Convertible.min_value
    SOURCE

    ctx = Savi.compiler.test_compile([source], :reparse)
    ctx.errors.should be_empty

    ctx.root_docs.first.to_a.should eq [:doc,
      [:declare,
        [:ident, "trait"],
        [:relate, [:ident, "Mumeric"], [:op, "."], [:ident, "Convertible"]]
      ],
      [:declare,
        [:ident, "class"],
        [:qualify, [:ident, "Example"], [:group, "(",
          [:group, " ",
            [:ident, "T"],
            [:relate, [:ident, "Mumeric"], [:op, "."], [:ident, "Convertible"]]
          ]
        ]],
        [:declare,
          [:ident, "fun"],
          [:qualify, [:ident, "example"], [:group, "(",
            [:group, " ",
              [:ident, "value"],
              [:relate, [:ident, "Mumeric"], [:op, "."], [:ident, "Convertible"]]
            ]
          ]],
          [:relate, [:ident, "Mumeric"], [:op, "."], [:ident, "Convertible"]],
          [:group, ":",
            [:relate,
              [:relate, [:ident, "Mumeric"], [:op, "."], [:ident, "Convertible"]],
              [:op, "."],
              [:ident, "min_value"]
            ]
          ]
        ]
      ]
    ]

    type = ctx.namespace[source]["Example"].resolve(ctx).as(Savi::Program::Type)
    func = ctx.namespace.find_func!(ctx, source, "Example", "example")
    type.params.not_nil!.to_a.should eq [:group, "(", [:relate,
      [:ident, "T"],
      [:op, "EXPLICITTYPE"],
      [:ident, "Mumeric.Convertible"],
    ]]
    func.params.not_nil!.to_a.should eq [:group, "(", [:relate,
      [:ident, "value"],
      [:op, "EXPLICITTYPE"],
      [:ident, "Mumeric.Convertible"],
    ]]
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:call, [:ident, "Mumeric.Convertible"], [:ident, "min_value"]]
    ]

    # # Compiling again should yield an equivalent program tree:
    # ctx2 = Savi.compiler.test_compile([source], :reparse)
    # ctx.program.packages.should eq ctx2.program.packages
  end
end
