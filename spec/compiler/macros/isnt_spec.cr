describe Mare::Compiler::Macros do
  describe "isnt" do
    it "is transformed into a relate of relate" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (foo Opaque, bar Opaque)
          foo isnt bar
      SOURCE

      ctx = Mare::Compiler.compile([source], :macros)

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:relate,
            [:relate, [:ident, "foo"], [:op, "is"], [:ident, "bar"]],
            [:op, "."],
            [:ident, "not"],
          ],
        ],
      ]
    end

    it "complains if there are too few terms" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          foo isnt
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          foo isnt
          ^~~~~~~~

      - this term is one of the two operands whose identity is to be compared:
        from (example):3:
          foo isnt
          ^~~

      - expected a term: the other of the two operands whose identity is to be compared:
        from (example):3:
          foo isnt
          ^~~~~~~~
      MSG

      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end

    it "complains if there are too many terms" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          foo isnt bar food
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          foo isnt bar food
          ^~~~~~~~~~~~~~~~~

      - this term is one of the two operands whose identity is to be compared:
        from (example):3:
          foo isnt bar food
          ^~~

      - this term is the other of the two operands whose identity is to be compared:
        from (example):3:
          foo isnt bar food
                   ^~~

      - this is an excessive term:
        from (example):3:
          foo isnt bar food
                       ^~~~
      MSG

      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end
  end
end
