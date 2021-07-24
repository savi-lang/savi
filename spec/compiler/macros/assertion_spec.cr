describe Savi::Compiler::Macros do
  describe "assert EXPR" do
    it "is transformed into Assert.condition" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          assert True
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(", [:call,
        [:ident, "Assert"],
        [:ident, "condition"],
        [:group, "(", 
          [:ident, "@"],
          [:ident, "True"],
        ]
      ]]
    end
  end

  describe "assert EXP1 <op> EXP2" do
    it "is transformed into Assert.relation" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          foo = "foo"
          assert SideEffects.call != foo
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.terms[1].to_a.should eq [:group, "(",
        [:relate,
          [:ident, "hygienic_macros_local.1"],
          [:op, "="],
          [:call, [:ident, "SideEffects"], [:ident, "call"]],
        ],
        [:call,
          [:ident, "Assert"],
          [:ident, "relation"],
          [:group, "(", 
            [:ident, "@"],
            [:string, "!=", nil],
            [:ident, "hygienic_macros_local.1"],
            [:ident, "foo"],
            [:relate, [:ident, "hygienic_macros_local.1"], [:op, "!="], [:ident, "foo"]]
          ]
        ]
      ]
    end
  end
end
