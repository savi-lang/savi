describe Mare::Compiler::Macros do
  describe "try" do
    it "is transformed into a try" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          try (error! | True)
      SOURCE

      ctx = Mare::Compiler.compile([source], :macros)

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:try,
            [:group, "(", [:jump, "error"]],
            [:group, "(", [:ident, "True"]],
          ],
        ],
      ]
    end

    it "complains if the number of terms is more than 1" do
      source = Mare::Source.new_example <<-SOURCE
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
        else clause to execute if the body errors (partitioned by `|`):
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

      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end

    it "complains if the delimited body has more than 2 sections" do
      source = Mare::Source.new_example <<-SOURCE
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
               ^~~~~~~

      - this section is the body to be executed if the previous errored (the "else" case):
        from (example):3:
          try (error! | True | what | now)
                       ^~~~~~

      - this is an excessive section:
        from (example):3:
          try (error! | True | what | now)
                              ^~~~~~

      - this is an excessive section:
        from (example):3:
          try (error! | True | what | now)
                                     ^~~~
      MSG

      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end
  end
end
