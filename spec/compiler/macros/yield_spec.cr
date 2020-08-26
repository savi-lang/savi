describe Mare::Compiler::Macros do
  describe "yield" do
    it "is transformed into a yield" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          yield True
      SOURCE

      ctx = Mare.compiler.compile([source], :macros)

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:yield, [:ident, "True"]],
        ],
      ]
    end

    it "complains if the number of terms is more than 1" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new
          yield True what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          yield True what now
          ^~~~~~~~~~~~~~~~~~~

      - this term is the value to be yielded out to the calling function:
        from (example):3:
          yield True what now
                ^~~~

      - this is an excessive term:
        from (example):3:
          yield True what now
                     ^~~~

      - this is an excessive term:
        from (example):3:
          yield True what now
                          ^~~
      MSG

      expect_raises Mare::Error, expected do
        Mare.compiler.compile([source], :macros)
      end
    end
  end
end
