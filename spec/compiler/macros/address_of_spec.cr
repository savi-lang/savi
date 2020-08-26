describe Mare::Compiler::Macros do
  describe "address_of" do
    it "is transformed into a prefix" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          t = 1
          address_of t
      SOURCE

      ctx = Mare::Compiler.compile([source], :macros)

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a[3].should eq [:group, "(",
        [:prefix, [:op, "address_of"], [:ident, "t"]]
      ]
    end

    it "complains if there are too many terms" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          t = 1
          address_of t 5
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):4:
          address_of t 5
          ^~~~~~~~~~~~~~

      - this term is the local variable whose address is to be referenced:
        from (example):4:
          address_of t 5
                     ^

      - this is an excessive term:
        from (example):4:
          address_of t 5
                       ^
      MSG

      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end
  end
end
