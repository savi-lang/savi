describe Mare::Compiler::Macros do
  describe "source_code_pos_of_arg" do
    it "is transformed into a prefix" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (foo String, bar SourceCodePos = source_code_pos_of_arg foo)
      SOURCE
      
      ctx = Mare::Compiler.compile([source], :macros)
      
      func = ctx.namespace.find_func!("Main", "new")
      func.params.not_nil!.to_a.should eq [:group, "(",
        [:group, " ", [:ident, "foo"], [:ident, "String"]],
        [:relate,
          [:group, " ", [:ident, "bar"], [:ident, "SourceCodePos"]],
          [:op, "="],
          [:group, "(",
            [:prefix, [:op, "SOURCECODEPOSOFARG"], [:ident, "foo"]],
          ],
        ],
      ]
    end
    
    it "complains if there are too many terms" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (foo String, bar SourceCodePos = source_code_pos_of_arg foo bar)
      SOURCE
      
      expected = <<-MSG
      This macro has too many terms:
      from (example):2:
        :new (foo String, bar SourceCodePos = source_code_pos_of_arg foo bar)
                                              ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      
      - this term is the parameter whose argument source code should be captured:
        from (example):2:
        :new (foo String, bar SourceCodePos = source_code_pos_of_arg foo bar)
                                                                     ^~~
      
      - this is an excessive term:
        from (example):2:
        :new (foo String, bar SourceCodePos = source_code_pos_of_arg foo bar)
                                                                         ^~~
      MSG
      
      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end
    
    it "complains if the term isn't an identifier" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (foo String, bar SourceCodePos = source_code_pos_of_arg 99)
      SOURCE
      
      expected = <<-MSG
      Expected this term to be an identifier:
      from (example):2:
        :new (foo String, bar SourceCodePos = source_code_pos_of_arg 99)
                                                                     ^~
      MSG
      
      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end
    
    it "complains if the identifier isn't a parameter" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (foo String, bar SourceCodePos = source_code_pos_of_arg food)
      SOURCE
      
      expected = <<-MSG
      Expected this term to be the identifier of a parameter:
      from (example):2:
        :new (foo String, bar SourceCodePos = source_code_pos_of_arg food)
                                                                     ^~~~
      
      - it is supposed to refer to one of the parameters listed here:
        from (example):2:
        :new (foo String, bar SourceCodePos = source_code_pos_of_arg food)
             ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      MSG
      
      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end
    
    it "complains if the macro isn't used as the default arg of a parameter" do
      source = Mare::Source.new_example <<-SOURCE
      :actor Main
        :new (foo String)
          bar SourceCodePos = source_code_pos_of_arg foo
      SOURCE
      
      expected = <<-MSG
      Expected this macro to be used as the default argument of a parameter:
      from (example):3:
          bar SourceCodePos = source_code_pos_of_arg foo
                              ^~~~~~~~~~~~~~~~~~~~~~~~~~
      
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
