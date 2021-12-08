describe Savi::Compiler::Macros do
  describe "reflection_of_runtime_type_name" do
    it "is transformed into a prefix" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          reflection_of_runtime_type_name @
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:prefix, [:op, "reflection_of_runtime_type_name"], [:ident, "@"]],
        ],
      ]
    end

    it "complains if there are too many terms" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          reflection_of_runtime_type_name @ @
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          reflection_of_runtime_type_name @ @
          ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the reference whose type name is to be reflected at runtime:
        from (example):3:
          reflection_of_runtime_type_name @ @
                                          ^

      - this is an excessive term:
        from (example):3:
          reflection_of_runtime_type_name @ @
                                            ^
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
