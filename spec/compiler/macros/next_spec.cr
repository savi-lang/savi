describe Mare::Compiler::Macros do
  describe "next" do
    it "is transformed into a jump" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example
          while True (
            next
          )
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Nexts", "example")
      func.body.not_nil!
        .terms.first.as(Mare::AST::Group)
        .terms.first.as(Mare::AST::Loop)
        .body.as(Mare::AST::Group)
        .terms.first.to_a
        .should eq \
        [:jump, "next", [:ident, "None"]]
    end

    it "can have an explicit value" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example
          while True (
            next "value"
          )
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Nexts", "example")
      func.body.not_nil!
        .terms.first.as(Mare::AST::Group)
        .terms.first.as(Mare::AST::Loop)
        .body.as(Mare::AST::Group)
        .terms.first.to_a
        .should eq [:group, "(",
        [:jump, "next", [:string, "value", nil]]
      ]
    end

    it "can be conditional with `if`" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example(cond_1, cond_2)
          while True (
            next if cond_1
            next "value" if cond_2
          )
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Nexts", "example")
      func.body.not_nil!
        .terms.first.as(Mare::AST::Group)
        .terms.first.as(Mare::AST::Loop)
        .body.as(Mare::AST::Group)
        .terms.first.to_a
        .should eq [:group, "(",
        [:choice,
          [[:ident, "cond_1"], [:jump, "next", [:ident, "None"]]],
          [[:ident, "True"], [:ident, "None"]],
        ],
      ]
      func.body.not_nil!
        .terms.first.as(Mare::AST::Group)
        .terms.first.as(Mare::AST::Loop)
        .body.as(Mare::AST::Group)
        .terms[1].to_a
        .should eq [:group, "(",
        [:choice,
          [[:ident, "cond_2"], [:jump, "next", [:string, "value", nil]]],
          [[:ident, "True"], [:ident, "None"]],
        ],
      ]
    end

    it "complains if there are extra terms after the `if` condition" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example(cond)
          while True (
            next if cond what now
          )
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):4:
            next if cond what now
            ^~~~~~~~~~~~~~~~~~~~~

      - this term is the condition that causes it to skip to the next iteration:
        from (example):4:
            next if cond what now
                    ^~~~

      - this is an excessive term:
        from (example):4:
            next if cond what now
                         ^~~~

      - this is an excessive term:
        from (example):4:
            next if cond what now
                              ^~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there are extra terms after the value and `if`" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example(cond)
          while True (
            next "value" if cond what now
          )
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):4:
            next "value" if cond what now
            ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the value to finish this block with:
        from (example):4:
            next "value" if cond what now
                  ^~~~~

      - this term is the condition that causes it to skip to the next iteration:
        from (example):4:
            next "value" if cond what now
                            ^~~~

      - this is an excessive term:
        from (example):4:
            next "value" if cond what now
                                 ^~~~

      - this is an excessive term:
        from (example):4:
            next "value" if cond what now
                                      ^~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is no `if` condition term" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example(cond)
          while True (
            next if
          )
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):4:
            next if
            ^~~~~~~

      - expected a term: the condition that causes it to skip to the next iteration:
        from (example):4:
            next if
            ^~~~~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is a value but no `if` condition term" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example(cond)
          while True (
            next "value" if
          )
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):4:
            next "value" if
            ^~~~~~~~~~~~~~~

      - this term is the value to finish this block with:
        from (example):4:
            next "value" if
                  ^~~~~

      - expected a term: the condition that causes it to skip to the next iteration:
        from (example):4:
            next "value" if
            ^~~~~~~~~~~~~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "can be conditional with `unless`" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example(cond)
          while True (
            next unless cond
            next "value" unless cond
          )
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Nexts", "example")
      func.body.not_nil!
        .terms.first.as(Mare::AST::Group)
        .terms.first.as(Mare::AST::Loop)
        .body.as(Mare::AST::Group)
        .terms.first.to_a
        .should eq [:group, "(",
        [:choice,
          [[:ident, "cond"], [:ident, "None"]],
          [[:ident, "True"], [:jump, "next", [:ident, "None"]]],
        ],
      ]
      func.body.not_nil!
        .terms.first.as(Mare::AST::Group)
        .terms.first.as(Mare::AST::Loop)
        .body.as(Mare::AST::Group)
        .terms[1].to_a
        .should eq [:group, "(",
        [:choice,
          [[:ident, "cond"], [:ident, "None"]],
          [[:ident, "True"], [:jump, "next", [:string, "value", nil]]],
        ],
      ]
    end

    it "complains if there are extra terms after the `unless` condition" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example(cond)
          while True (
            next unless cond what now
          )
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):4:
            next unless cond what now
            ^~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the condition that prevents it from skipping to the next iteration:
        from (example):4:
            next unless cond what now
                        ^~~~

      - this is an excessive term:
        from (example):4:
            next unless cond what now
                             ^~~~

      - this is an excessive term:
        from (example):4:
            next unless cond what now
                                  ^~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there are extra terms after the value and `unless`" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example(cond)
          while True (
            next "value" unless cond what now
          )
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):4:
            next "value" unless cond what now
            ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the value to finish this block with:
        from (example):4:
            next "value" unless cond what now
                  ^~~~~

      - this term is the condition that prevents it from skipping to the next iteration:
        from (example):4:
            next "value" unless cond what now
                                ^~~~

      - this is an excessive term:
        from (example):4:
            next "value" unless cond what now
                                     ^~~~

      - this is an excessive term:
        from (example):4:
            next "value" unless cond what now
                                          ^~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is no `unless` condition term" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example(cond)
          while True (
            next unless
          )
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):4:
            next unless
            ^~~~~~~~~~~

      - expected a term: the condition that prevents it from skipping to the next iteration:
        from (example):4:
            next unless
            ^~~~~~~~~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is a value but no `unless` condition term" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Nexts
        :fun example(cond)
          while True (
            next "value" unless
          )
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):4:
            next "value" unless
            ^~~~~~~~~~~~~~~~~~~

      - this term is the value to finish this block with:
        from (example):4:
            next "value" unless
                  ^~~~~

      - expected a term: the condition that prevents it from skipping to the next iteration:
        from (example):4:
            next "value" unless
            ^~~~~~~~~~~~~~~~~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
