describe Mare::Compiler::Lambda do
  it "handles thunks (lambdas with no parameters)" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun thunk
        apple = ^(Fruit.new("apple").flavor)
    SOURCE

    ctx = Mare::Compiler.compile([source], :lambda)

    func = ctx.namespace.find_func!("Example", "thunk")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "apple"],
        [:op, "="],
        [:group, "(", [:ident, "Example.thunk.^1"]],
      ],
    ]

    lambda =
      ctx.program.types.find(&.ident.value.==("Example.thunk.^1")).not_nil!
        .find_func!("call")
    lambda.params.should eq nil
    lambda.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:relate, [:ident, "Fruit"], [:op, "."], [:qualify,
          [:ident, "new"], [:group, "(", [:string, "apple"]]
        ]],
        [:op, "."],
        [:ident, "flavor"],
      ],
    ]
  end

  it "handles lambdas with parameters" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun lambdas
        apple = ^(Fruit.new(^1, ^2).flavor)
    SOURCE

    ctx = Mare::Compiler.compile([source], :lambda)

    func = ctx.namespace.find_func!("Example", "lambdas")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "apple"],
        [:op, "="],
        [:group, "(", [:ident, "Example.lambdas.^1"]],
      ],
    ]

    lambda =
      ctx.program.types.find(&.ident.value.==("Example.lambdas.^1")).not_nil!
        .find_func!("call")
    lambda.params.not_nil!.to_a.should eq [:group, "(",
      [:ident, "1"],
      [:ident, "2"],
    ]
    lambda.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:relate, [:ident, "Fruit"], [:op, "."], [:qualify,
          [:ident, "new"], [:group, "(", [:ident, "1"], [:ident, "2"]]
        ]],
        [:op, "."],
        [:ident, "flavor"],
      ],
    ]
  end

  it "raises an error if a lambda parameter reference is outside a lambda" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun no_lambda
        apple = ^1
    SOURCE

    expected = <<-MSG
    A lambda parameter can't be used outside of a lambda:
    from (example):3:
        apple = ^1
                ^~
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :lambda)
    end
  end
end
