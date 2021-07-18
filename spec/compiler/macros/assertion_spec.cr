describe Savi::Compiler::Macros do
  describe "assert" do
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
end
