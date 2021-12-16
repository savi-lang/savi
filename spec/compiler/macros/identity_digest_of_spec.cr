describe Savi::Compiler::Macros do
  describe "identity_digest_of" do
    it "is transformed into a prefix" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          identity_digest_of @
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:prefix, [:op, "identity_digest_of"], [:ident, "@"]],
        ],
      ]
    end

    it "complains if there are too many terms" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          identity_digest_of @ @
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          identity_digest_of @ @
          ^~~~~~~~~~~~~~~~~~~~~~

      - this term is the value whose identity is to be hashed:
        from (example):3:
          identity_digest_of @ @
                             ^

      - this is an excessive term:
        from (example):3:
          identity_digest_of @ @
                               ^
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
