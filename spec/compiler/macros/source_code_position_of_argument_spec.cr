describe Savi::Compiler::Macros do
  describe "source_code_position_of_argument" do
    it "is transformed into a prefix" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new (
          foo String
          bar SourceCodePosition = source_code_position_of_argument foo
        )
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Main", "new")
      func.params.not_nil!.to_a.should eq [:group, "(",
        [:relate, [:ident, "foo"], [:op, "EXPLICITTYPE"], [:ident, "String"]],
        [:relate,
          [:relate,
            [:ident, "bar"],
            [:op, "EXPLICITTYPE"],
            [:ident, "SourceCodePosition"],
          ],
          [:op, "DEFAULTPARAM"],
          [:group, "(",
            [:prefix, [:op, "source_code_position_of_argument"], [:ident, "foo"]],
          ],
        ],
      ]
    end

    it "complains if there are too many terms" do
      source = Savi::Source.new_example <<-SOURCE
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

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if the term isn't an identifier" do
      source = Savi::Source.new_example <<-SOURCE
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

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if the identifier isn't a parameter" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new (
          foo String
          bar SourceCodePosition = source_code_position_of_argument food
        )
      SOURCE

      expected = <<-MSG
      Expected this term to be the identifier of a parameter, or `yield`:
      from (example):4:
          bar SourceCodePosition = source_code_position_of_argument food
                                                                    ^~~~

      - it is supposed to refer to one of the parameters listed here:
        from (example):2:
        :new (
             ^···
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "won't complain if the identifier is yield" do
      source = Savi::Source.new_example <<-SOURCE
      :actor Main
        :new (
          foo String
          bar SourceCodePosition = source_code_position_of_argument yield
        )
      SOURCE

      Savi.compiler.test_compile([source], :macros).errors.should be_empty
    end

    it "complains if the macro isn't used as the default arg of a parameter" do
      source = Savi::Source.new_example <<-SOURCE
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

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
