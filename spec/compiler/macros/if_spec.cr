describe Savi::Compiler::Macros do
  describe "if" do
    it "is transformed into a choice" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          if True 42
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:choice,
            [[:ident, "True"], [:integer, 42]],
            [[:ident, "True"], [:ident, "None"]],
          ],
        ],
      ]
    end

    it "complains if the number of terms is more than 2" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          if True (
            False
          ) what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          if True (
          ^~~~~~~~~···

      - this term is the condition to be satisfied:
        from (example):3:
          if True (
             ^~~~

      - this term is the body to be conditionally executed,
        including an optional else clause partitioned by `|`:
        from (example):3:
          if True (
                  ^···

      - this is an excessive term:
        from (example):5:
          ) what now
            ^~~~

      - this is an excessive term:
        from (example):5:
          ) what now
                 ^~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if the number of terms is less than 2" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          if True
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          if True
          ^~~~~~~

      - this term is the condition to be satisfied:
        from (example):3:
          if True
             ^~~~

      - expected a term: the body to be conditionally executed,
        including an optional else clause partitioned by `|`:
        from (example):3:
          if True
          ^~~~~~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "handles an optional else clause, delimited by |" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          if True (42 | 7)
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:choice,
            [[:ident, "True"], [:group, "(", [:integer, 42]]],
            [[:ident, "True"], [:group, "(", [:integer, 7]]],
          ],
        ],
      ]
    end

    it "complains if the delimited body has more than 2 sections" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new
          if True (42 | 7 | what | now)
      SOURCE

      expected = <<-MSG
      This grouping has too many sections:
      from (example):3:
          if True (42 | 7 | what | now)
                  ^~~~~~~~~~~~~~~~~~~~~

      - this section is the body to be executed when the condition is true:
        from (example):3:
          if True (42 | 7 | what | now)
                   ^~

      - this section is the body to be executed otherwise (the "else" case):
        from (example):3:
          if True (42 | 7 | what | now)
                        ^

      - this is an excessive section:
        from (example):3:
          if True (42 | 7 | what | now)
                            ^~~~

      - this is an excessive section:
        from (example):3:
          if True (42 | 7 | what | now)
                                   ^~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
