describe Savi::Compiler::Macros do
  describe "static_address_of_function" do
    it "is transformed into a relation" do
      source = Savi::Source.new_example <<-SOURCE
      :module _Math
        :fun non add(a U8, b U8): a + b

      :actor Main
        :new (env Env)
          static_address_of_function _Math.add
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":", [:group, "(", [:relate,
        [:ident, "_Math"],
        [:op, "static_address_of_function"],
        [:ident, "add"],
      ]]]
    end

    it "complains if there are too many terms" do
      source = Savi::Source.new_example <<-SOURCE
      :module _Math
        :fun non add(a U8, b U8): a + b

      :actor Main
        :new (env Env)
          static_address_of_function _Math.add _Math.add
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):6:
          static_address_of_function _Math.add _Math.add
          ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the function whose static address should be captured:
        from (example):6:
          static_address_of_function _Math.add _Math.add
                                     ^~~~~~~~~

      - this is an excessive term:
        from (example):6:
          static_address_of_function _Math.add _Math.add
                                               ^~~~~~~~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if the term isn't a call" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new (env Env)
          static_address_of_function 99
      SOURCE

      expected = <<-MSG
      Expected this term to be a type name and function name with a dot in between:
      from (example):3:
          static_address_of_function 99
                                     ^~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if the term has arguments" do
      source = Savi::Source.new_example <<-SOURCE
      :module _Math
        :fun non add(a U8, b U8): a + b

      :actor Main
        :new (env Env)
          static_address_of_function _Math.add(2, 2)
      SOURCE

      expected = <<-MSG
      Expected this function to have no arguments:
      from (example):6:
          static_address_of_function _Math.add(2, 2)
                                              ^~~~~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
