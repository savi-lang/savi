describe Mare::Compiler::Sugar do
  it "handles thunks (lambdas with no parameters)" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Example:
      fun thunk:
        apple = ^(Fruit.new("apple").flavor)
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :lambda)
    
    func = ctx.program.find_func!("Example", "thunk")
    func.body.not_nil!.to_a.should eq [:group, ":",
      [:relate,
        [:ident, "apple"],
        [:op, "="],
        [:group, "(", [:ident, "Example.thunk.^1"]],
      ],
    ]
    
    ctx.program.types.find(&.ident.value.==("Example.thunk.^1")).not_nil!
      .find_func!("call")
      .body.not_nil!.to_a.should eq [:group, ":",
        [:relate,
          [:relate, [:ident, "Fruit"], [:op, "."], [:qualify,
            [:ident, "new"], [:group, "(", [:string, "apple"]]
          ]],
          [:op, "."],
          [:ident, "flavor"],
        ],
      ]
  end
end
