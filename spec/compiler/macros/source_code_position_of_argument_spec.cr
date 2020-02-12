describe Mare::Compiler::Macros do
  describe "source_code_position_of_argument" do
    it "is transformed into a prefix" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (
          foo String
          bar SourceCodePosition = source_code_position_of_argument foo
        )
      SOURCE

      ctx = Mare::Compiler.compile([source], :macros)

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.params.not_nil!.to_a.should eq [:group, "(",
        [:group, " ", [:ident, "foo"], [:ident, "String"]],
        [:relate,
          [:group, " ", [:ident, "bar"], [:ident, "SourceCodePosition"]],
          [:op, "="],
          [:group, "(",
            [:prefix, [:op, "source_code_position_of_argument"], [:ident, "foo"]],
          ],
        ],
      ]
    end

    it "complains if there are too many terms" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (
          foo String
          bar SourceCodePosition = source_code_position_of_argument foo bar
        )
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):4:
          bar SourceCodePosition = source_code_position_of_argument foo bar
                                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the parameter whose argument source code should be captured:
        from (example):4:
          bar SourceCodePosition = source_code_position_of_argument foo bar
                                                                    ^~~

      - this is an excessive term:
        from (example):4:
          bar SourceCodePosition = source_code_position_of_argument foo bar
                                                                        ^~~
      MSG

      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end

    it "complains if the term isn't an identifier" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (
          foo String
          bar SourceCodePosition = source_code_position_of_argument 99
        )
      SOURCE

      expected = <<-MSG
      Expected this term to be an identifier:
      from (example):4:
          bar SourceCodePosition = source_code_position_of_argument 99
                                                                    ^~
      MSG

      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end

    it "complains if the identifier isn't a parameter" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (
          foo String
          bar SourceCodePosition = source_code_position_of_argument food
        )
      SOURCE

      expected = <<-MSG
      Expected this term to be the identifier of a parameter:
      from (example):4:
          bar SourceCodePosition = source_code_position_of_argument food
                                                                    ^~~~

      - it is supposed to refer to one of the parameters listed here:
        from (example):2:
        :new (
             ^···
      MSG

      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end

    it "complains if the macro isn't used as the default arg of a parameter" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (foo String)
          bar SourceCodePosition = source_code_position_of_argument foo
      SOURCE

      expected = <<-MSG
      Expected this macro to be used as the default argument of a parameter:
      from (example):3:
          bar SourceCodePosition = source_code_position_of_argument foo
                                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

      - it is supposed to be assigned to a parameter here:
        from (example):2:
        :new (foo String)
             ^~~~~~~~~~~~
      MSG

      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end
  end
end
