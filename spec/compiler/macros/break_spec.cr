describe Mare::Compiler::Macros do
  describe "break" do
    it "is transformed into a jump" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example
          while True (
            break
          )
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Breaks", "example")
      func.body.not_nil!
        .terms.first.as(Mare::AST::Group)
        .terms.first.as(Mare::AST::Loop)
        .body.as(Mare::AST::Group)
        .terms.first.to_a
        .should eq \
        [:jump, "break", [:ident, "None"]]
    end

    it "can have an explicit value" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example
          while True (
            break "value"
          )
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Breaks", "example")
      func.body.not_nil!
        .terms.first.as(Mare::AST::Group)
        .terms.first.as(Mare::AST::Loop)
        .body.as(Mare::AST::Group)
        .terms.first.to_a
        .should eq [:group, "(",
        [:jump, "break", [:string, "value", nil]]
      ]
    end

    it "can be conditional with `if`" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example(cond_1, cond_2)
          while True (
            break if cond_1
            break "value" if cond_2
          )
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Breaks", "example")
      func.body.not_nil!
        .terms.first.as(Mare::AST::Group)
        .terms.first.as(Mare::AST::Loop)
        .body.as(Mare::AST::Group)
        .terms.first.to_a
        .should eq [:group, "(",
        [:choice,
          [[:ident, "cond_1"], [:jump, "break", [:ident, "None"]]],
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
          [[:ident, "cond_2"], [:jump, "break", [:string, "value", nil]]],
          [[:ident, "True"], [:ident, "None"]],
        ],
      ]
    end

    it "complains if there are extra terms after the `if` condition" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example(cond)
          while True (
            break if cond what now
          )
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):4:
            break if cond what now
            ^~~~~~~~~~~~~~~~~~~~~~

      - this term is the condition that causes it to break the iteration:
        from (example):4:
            break if cond what now
                     ^~~~

      - this is an excessive term:
        from (example):4:
            break if cond what now
                          ^~~~

      - this is an excessive term:
        from (example):4:
            break if cond what now
                               ^~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there are extra terms after the value and `if`" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example(cond)
          while True (
            break "value" if cond what now
          )
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):4:
            break "value" if cond what now
            ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the result value to break iteration with:
        from (example):4:
            break "value" if cond what now
                   ^~~~~

      - this term is the condition that causes it to break the iteration:
        from (example):4:
            break "value" if cond what now
                             ^~~~

      - this is an excessive term:
        from (example):4:
            break "value" if cond what now
                                  ^~~~

      - this is an excessive term:
        from (example):4:
            break "value" if cond what now
                                       ^~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is no `if` condition term" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example(cond)
          while True (
            break if
          )
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):4:
            break if
            ^~~~~~~~

      - expected a term: the condition that causes it to break the iteration:
        from (example):4:
            break if
            ^~~~~~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is a value but no `if` condition term" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example(cond)
          while True (
            break "value" if
          )
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):4:
            break "value" if
            ^~~~~~~~~~~~~~~~

      - this term is the result value to break iteration with:
        from (example):4:
            break "value" if
                   ^~~~~

      - expected a term: the condition that causes it to break the iteration:
        from (example):4:
            break "value" if
            ^~~~~~~~~~~~~~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "can be conditional with `unless`" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example(cond)
          while True (
            break unless cond
            break "value" unless cond
          )
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Breaks", "example")
      func.body.not_nil!
        .terms.first.as(Mare::AST::Group)
        .terms.first.as(Mare::AST::Loop)
        .body.as(Mare::AST::Group)
        .terms.first.to_a
        .should eq [:group, "(",
        [:choice,
          [[:ident, "cond"], [:ident, "None"]],
          [[:ident, "True"], [:jump, "break", [:ident, "None"]]],
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
          [[:ident, "True"], [:jump, "break", [:string, "value", nil]]],
        ],
      ]
    end

    it "complains if there are extra terms after the `unless` condition" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example(cond)
          while True (
            break unless cond what now
          )
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):4:
            break unless cond what now
            ^~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the condition that prevents it from breaking the iteration:
        from (example):4:
            break unless cond what now
                         ^~~~

      - this is an excessive term:
        from (example):4:
            break unless cond what now
                              ^~~~

      - this is an excessive term:
        from (example):4:
            break unless cond what now
                                   ^~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there are extra terms after the value and `unless`" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example(cond)
          while True (
            break "value" unless cond what now
          )
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):4:
            break "value" unless cond what now
            ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the result value to break iteration with:
        from (example):4:
            break "value" unless cond what now
                   ^~~~~

      - this term is the condition that prevents it from breaking the iteration:
        from (example):4:
            break "value" unless cond what now
                                 ^~~~

      - this is an excessive term:
        from (example):4:
            break "value" unless cond what now
                                      ^~~~

      - this is an excessive term:
        from (example):4:
            break "value" unless cond what now
                                           ^~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is no `unless` condition term" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example(cond)
          while True (
            break unless
          )
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):4:
            break unless
            ^~~~~~~~~~~~

      - expected a term: the condition that prevents it from breaking the iteration:
        from (example):4:
            break unless
            ^~~~~~~~~~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is a value but no `unless` condition term" do
      source = Mare::Source.new_example <<-SOURCE
      :primitive Breaks
        :fun example(cond)
          while True (
            break "value" unless
          )
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):4:
            break "value" unless
            ^~~~~~~~~~~~~~~~~~~~

      - this term is the result value to break iteration with:
        from (example):4:
            break "value" unless
                   ^~~~~

      - expected a term: the condition that prevents it from breaking the iteration:
        from (example):4:
            break "value" unless
            ^~~~~~~~~~~~~~~~~~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
