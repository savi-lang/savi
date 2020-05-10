describe Mare::Compiler::Macros do
  describe "reflection_of_type" do
    it "is transformed into a prefix" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          reflection_of_type @
      SOURCE

      ctx = Mare::Compiler.compile([source], :macros)

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:prefix, [:op, "reflection_of_type"], [:ident, "@"]],
        ],
      ]
    end

    it "complains if there are too many terms" do
      source = Mare::Source.new_example <<-SOURCE
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

      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end
  end
end
