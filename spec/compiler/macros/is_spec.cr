describe Mare::Compiler::Macros do
  describe "is" do
    it "is transformed into a relate" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (foo Opaque, bar Opaque)
          foo is bar
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:relate, [:ident, "foo"], [:op, "is"], [:ident, "bar"]],
        ],
      ]
    end

    it "complains if there are too few terms" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          foo is
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          foo is
          ^~~~~~

      - this term is one of the two operands whose identity is to be compared:
        from (example):3:
          foo is
          ^~~

      - expected a term: the other of the two operands whose identity is to be compared:
        from (example):3:
          foo is
          ^~~~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there are too many terms" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          foo is bar food
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          foo is bar food
          ^~~~~~~~~~~~~~~

      - this term is one of the two operands whose identity is to be compared:
        from (example):3:
          foo is bar food
          ^~~

      - this term is the other of the two operands whose identity is to be compared:
        from (example):3:
          foo is bar food
                 ^~~

      - this is an excessive term:
        from (example):3:
          foo is bar food
                     ^~~~
      MSG

      Mare.compiler.compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
