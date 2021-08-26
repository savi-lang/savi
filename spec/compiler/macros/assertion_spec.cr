describe Savi::Compiler::Macros do
  describe "assert EXPR" do
    it "is transformed into Assert.condition" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          assert: True
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
          assert: SideEffects.call != "foo"
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(",
        [:relate,
          [:relate,
            [:ident, "hygienic_macros_local.1"],
            [:op, "EXPLICITTYPE"],
            [:ident, "box"]],
          [:op, "="],
          [:call, [:ident, "SideEffects"], [:ident, "call"]],
        ],
        [:relate,
          [:relate,
            [:ident, "hygienic_macros_local.2"],
            [:op, "EXPLICITTYPE"],
            [:ident, "box"]],
          [:op, "="],
          [:string, "foo", nil],
        ],
        [:call,
          [:ident, "Assert"],
          [:ident, "relation"],
          [:group, "(",
            [:ident, "@"],
            [:string, "!=", nil],
            [:ident, "hygienic_macros_local.1"],
            [:ident, "hygienic_macros_local.2"],
            [:relate,
              [:ident, "hygienic_macros_local.1"],
              [:op, "!="],
              [:ident, "hygienic_macros_local.2"]]
          ]
        ]
      ]
    end
  end
end
