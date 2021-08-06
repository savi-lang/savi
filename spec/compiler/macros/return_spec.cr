describe Savi::Compiler::Macros do
  describe "return" do
    it "is transformed into a jump" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example
          return
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Returns", "example")
      func.body.not_nil!.terms.first.to_a.should eq \
        [:jump, "return", [:ident, "None"]]
    end

    it "it can be nested, as silly as that is" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example
          @
          return (
            @
            return "value"
            @
          )
          @
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Returns", "example")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:ident, "@"],
        [:group, "(",
          [:jump, "return", [:group, "(",
            [:ident, "@"],
            [:group, "(", [:jump, "return", [:string, "value", nil]]],
            [:ident, "@"],
          ]],
        ],
        [:ident, "@"],
      ]
    end

    it "can have an explicit value" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example
          return "value"
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Returns", "example")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(",
        [:jump, "return", [:string, "value", nil]]
      ]
    end

    it "can be conditional with `if`" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example(cond_1, cond_2)
          return if cond_1
          return "value" if cond_2
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Returns", "example")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(",
        [:choice,
          [[:ident, "cond_1"], [:jump, "return", [:ident, "None"]]],
          [[:ident, "True"], [:ident, "None"]],
        ],
      ]
      func.body.not_nil!.terms[1].to_a.should eq [:group, "(",
        [:choice,
          [[:ident, "cond_2"], [:jump, "return", [:string, "value", nil]]],
          [[:ident, "True"], [:ident, "None"]],
        ],
      ]
    end

    it "complains if there are extra terms after the `if` condition" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example(cond)
          return if cond what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          return if cond what now
          ^~~~~~~~~~~~~~~~~~~~~~~

      - this term is the condition that causes it to return early:
        from (example):3:
          return if cond what now
                    ^~~~

      - this is an excessive term:
        from (example):3:
          return if cond what now
                         ^~~~

      - this is an excessive term:
        from (example):3:
          return if cond what now
                              ^~~
      MSG

      Savi.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there are extra terms after the value and `if`" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example(cond)
          return "value" if cond what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          return "value" if cond what now
          ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the value to return:
        from (example):3:
          return "value" if cond what now
                 ^~~~~~~

      - this term is the condition that causes it to return early:
        from (example):3:
          return "value" if cond what now
                            ^~~~

      - this is an excessive term:
        from (example):3:
          return "value" if cond what now
                                 ^~~~

      - this is an excessive term:
        from (example):3:
          return "value" if cond what now
                                      ^~~
      MSG

      Savi.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is no `if` condition term" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example(cond)
          return if
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          return if
          ^~~~~~~~~

      - expected a term: the condition that causes it to return early:
        from (example):3:
          return if
          ^~~~~~~~~
      MSG

      Savi.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is a value but no `if` condition term" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example(cond)
          return "value" if
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          return "value" if
          ^~~~~~~~~~~~~~~~~

      - this term is the value to return:
        from (example):3:
          return "value" if
                 ^~~~~~~

      - expected a term: the condition that causes it to return early:
        from (example):3:
          return "value" if
          ^~~~~~~~~~~~~~~~~
      MSG

      Savi.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "can be conditional with `unless`" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example(cond)
          return unless cond
          return "value" unless cond
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Returns", "example")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(",
        [:choice,
          [[:ident, "cond"], [:ident, "None"]],
          [[:ident, "True"], [:jump, "return", [:ident, "None"]]],
        ],
      ]
      func.body.not_nil!.terms[1].to_a.should eq [:group, "(",
        [:choice,
          [[:ident, "cond"], [:ident, "None"]],
          [[:ident, "True"], [:jump, "return", [:string, "value", nil]]],
        ],
      ]
    end

    it "complains if there are extra terms after the `unless` condition" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example(cond)
          return unless cond what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          return unless cond what now
          ^~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the condition that prevents it from returning early:
        from (example):3:
          return unless cond what now
                        ^~~~

      - this is an excessive term:
        from (example):3:
          return unless cond what now
                             ^~~~

      - this is an excessive term:
        from (example):3:
          return unless cond what now
                                  ^~~
      MSG

      Savi.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there are extra terms after the value and `unless`" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example(cond)
          return "value" unless cond what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          return "value" unless cond what now
          ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the value to return:
        from (example):3:
          return "value" unless cond what now
                 ^~~~~~~

      - this term is the condition that prevents it from returning early:
        from (example):3:
          return "value" unless cond what now
                                ^~~~

      - this is an excessive term:
        from (example):3:
          return "value" unless cond what now
                                     ^~~~

      - this is an excessive term:
        from (example):3:
          return "value" unless cond what now
                                          ^~~
      MSG

      Savi.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is no `unless` condition term" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example(cond)
          return unless
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          return unless
          ^~~~~~~~~~~~~

      - expected a term: the condition that prevents it from returning early:
        from (example):3:
          return unless
          ^~~~~~~~~~~~~
      MSG

      Savi.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is a value but no `unless` condition term" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Returns
        :fun example(cond)
          return "value" unless
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          return "value" unless
          ^~~~~~~~~~~~~~~~~~~~~

      - this term is the value to return:
        from (example):3:
          return "value" unless
                 ^~~~~~~

      - expected a term: the condition that prevents it from returning early:
        from (example):3:
          return "value" unless
          ^~~~~~~~~~~~~~~~~~~~~
      MSG

      Savi.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
