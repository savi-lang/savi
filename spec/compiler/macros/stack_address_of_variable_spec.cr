describe Savi::Compiler::Macros do
  describe "stack_address_of_variable" do
    it "is transformed into a prefix" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new (env Env)
          foo = 99
          stack_address_of_variable foo
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:relate, [:ident, "foo"], [:op, "="], [:integer, 99]],
        [:group, "(", [:prefix, [:op, "stack_address_of_variable"], [:ident, "foo"]]],
      ]
    end

    it "complains if there are too many terms" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new (env Env)
          foo = 99
          bar = 100
          stack_address_of_variable foo bar
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):5:
          stack_address_of_variable foo bar
          ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the local variable whose stack address should be captured:
        from (example):5:
          stack_address_of_variable foo bar
                                    ^~~

      - this is an excessive term:
        from (example):5:
          stack_address_of_variable foo bar
                                        ^~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if the term isn't an identifier" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new (env Env)
          stack_address_of_variable 99
      SOURCE

      expected = <<-MSG
      Expected this term to be an identifier:
      from (example):3:
          stack_address_of_variable 99
                                    ^~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
