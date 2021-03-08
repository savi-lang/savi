describe Mare::Compiler::Macros do
  describe "while" do
    it "is transformed into a choice" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          while True 42
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:loop, [:ident, "True"], [:integer, 42], [:ident, "None"]],
        ],
      ]
    end

    it "complains if the number of terms is more than 2" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          while True (
            False
          ) what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          while True (
          ^~~~~~~~~~~~···

      - this term is the condition to be satisfied:
        from (example):3:
          while True (
                ^~~~

      - this term is the body to be conditionally executed in a loop,
        including an optional else clause partitioned by `|`:
        from (example):3:
          while True (
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

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if the number of terms is less than 2" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          while True
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          while True
          ^~~~~~~~~~

      - this term is the condition to be satisfied:
        from (example):3:
          while True
                ^~~~

      - expected a term: the body to be conditionally executed in a loop,
        including an optional else clause partitioned by `|`:
        from (example):3:
          while True
          ^~~~~~~~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "handles an optional else clause, delimited by |" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          while True (42 | 7)
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:loop,
            [:ident, "True"],
            [:group, "(", [:integer, 42_u64]],
            [:group, "(", [:integer, 7_u64]],
          ],
        ],
      ]
    end

    it "complains if the delimited body has more than 2 sections" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          while True (42 | 7 | what | now)
      SOURCE

      expected = <<-MSG
      This grouping has too many sections:
      from (example):3:
          while True (42 | 7 | what | now)
                     ^~~~~~~~~~~~~~~~~~~~~

      - this section is the body to be executed on loop when the condition is true:
        from (example):3:
          while True (42 | 7 | what | now)
                      ^~~

      - this section is the body to be executed otherwise (the "else" case):
        from (example):3:
          while True (42 | 7 | what | now)
                          ^~~

      - this is an excessive section:
        from (example):3:
          while True (42 | 7 | what | now)
                              ^~~~~~

      - this is an excessive section:
        from (example):3:
          while True (42 | 7 | what | now)
                                     ^~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
