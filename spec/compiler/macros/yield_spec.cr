describe Savi::Compiler::Macros do
  describe "yield" do
    it "is transformed into a yield" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Yields
        :fun example
          yield "value"
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Yields", "example")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:yield, [:string, "value", nil]],
        ],
      ]
    end

    it "complains if there are more terms after the value" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Yields
        :fun example
          yield "value" what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          yield "value" what now
          ^~~~~~~~~~~~~~~~~~~~~~

      - this term is the value to be yielded out to the calling function:
        from (example):3:
          yield "value" what now
                 ^~~~~

      - this is an excessive term:
        from (example):3:
          yield "value" what now
                        ^~~~

      - this is an excessive term:
        from (example):3:
          yield "value" what now
                             ^~~
      MSG

      Savi.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "can be conditional with `if`" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Yields
        :fun example(cond)
          yield "value" if cond
      SOURCE

      ctx = Savi.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Yields", "example")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(",
        [:choice,
          [[:ident, "cond"], [:yield, [:string, "value", nil]]],
          [[:ident, "True"], [:ident, "None"]],
        ],
      ]
    end

    it "complains if there are extra terms after the value and `if`" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Yields
        :fun example(cond)
          yield "value" if cond what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          yield "value" if cond what now
          ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the value to be yielded out to the calling function:
        from (example):3:
          yield "value" if cond what now
                 ^~~~~

      - this term is the condition that causes it to yield:
        from (example):3:
          yield "value" if cond what now
                           ^~~~

      - this is an excessive term:
        from (example):3:
          yield "value" if cond what now
                                ^~~~

      - this is an excessive term:
        from (example):3:
          yield "value" if cond what now
                                     ^~~
      MSG

      Savi.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is no `if` condition term" do
      source = Savi::Source.new_example <<-SOURCE
      :primitive Yields
        :fun example(cond)
          yield "value" if
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          yield "value" if
          ^~~~~~~~~~~~~~~~

      - this term is the value to be yielded out to the calling function:
        from (example):3:
          yield "value" if
                 ^~~~~

      - expected a term: the condition that causes it to yield:
        from (example):3:
          yield "value" if
          ^~~~~~~~~~~~~~~~
      MSG

      Savi.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
