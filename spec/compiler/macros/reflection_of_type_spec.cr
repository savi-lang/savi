describe Savi::Compiler::Macros do
  describe "reflection_of_type" do
    it "is transformed into a prefix" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          reflection_of_type @
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:prefix, [:op, "reflection_of_type"], [:ident, "@"]],
        ],
      ]
    end

    it "complains if there are too many terms" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          reflection_of_type @ @
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          reflection_of_type @ @
          ^~~~~~~~~~~~~~~~~~~~~~

      - this term is the reference whose compile-time type is to be reflected:
        from (example):3:
          reflection_of_type @ @
                             ^

      - this is an excessive term:
        from (example):3:
          reflection_of_type @ @
                               ^
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
