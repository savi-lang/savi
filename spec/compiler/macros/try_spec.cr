describe Savi::Compiler::Macros do
  describe "try" do
    it "is transformed into a try" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          try (error! | True)
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:try,
            [:group, "(", [:jump, "error", [:ident, "None"]]],
            [:group, "(", [:ident, "True"]],
          ],
        ],
      ]
    end

    it "complains if the number of terms is more than 1" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          try (error! | True) what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          try (error! | True) what now
          ^~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the body to be attempted, followed by an optional
        else clause (partitioned by `|`) to execute if there is an error;
        if there are three clauses, then the middle one is treated as a
        an expression that captures the error value in a local variable,
        possibly constraining the type of error values that are allowed:
        from (example):3:
          try (error! | True) what now
              ^~~~~~~~~~~~~~~

      - this is an excessive term:
        from (example):3:
          try (error! | True) what now
                              ^~~~

      - this is an excessive term:
        from (example):3:
          try (error! | True) what now
                                   ^~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if the delimited body has more than 2 sections" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          try (error! | True | what | now)
      SOURCE

      expected = <<-MSG
      This grouping has too many sections:
      from (example):3:
          try (error! | True | what | now)
              ^~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this section is the body to attempt to execute fully:
        from (example):3:
          try (error! | True | what | now)
               ^~~~~~

      - this section is an optional local variable expression to bind a caught error value:
        from (example):3:
          try (error! | True | what | now)
                        ^~~~

      - this section is the body to be executed if the previous errored (the "else" case):
        from (example):3:
          try (error! | True | what | now)
                               ^~~~

      - this is an excessive section:
        from (example):3:
          try (error! | True | what | now)
                                      ^~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
