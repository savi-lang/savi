describe Mare::Compiler::Macros do
  describe "if" do
    it "is transformed into a choice" do
      source = Mare::Source.new "(example)", <<-SOURCE
      actor Main:
        new:
          if True 42
      SOURCE
      
      ctx = Mare::Compiler.compile(source, limit: Mare::Compiler::Macros)
      
      func = ctx.program.find_func!("Main", "new")
      func.body.not_nil!.to_a.should eq [:group, ":",
        [:group, "(",
          [:choice,
            [[:ident, "True"], [:integer, 42]],
            [[:ident, "True"], [:ident, "None"]],
          ],
        ],
        [:ident, "@"],
      ]
    end
    
    it "complains if the number of terms is more than 2" do
      source = Mare::Source.new "(example)", <<-SOURCE
      actor Main:
        new:
          if True (
            False
          ) what now
      SOURCE
      
      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          if True (
          ^~~~~~~~~···
      - this term is the condition to be satisfied:
      from (example):3:
          if True (
             ^~~~
      - this term is the body to be conditionally executed,
        including an optional else clause partitioned by `|`:
      from (example):3:
          if True (
                  ^···
      - this is an excessive term:
      from (example):5:
          ) what now
            ^~~~
      - this is an excessive term:
      from (example):5:
          ) what now
                 ^~~
      MSG
      
      expect_raises Mare::Compiler::Macros::Error, expected do
        Mare::Compiler.compile(source, limit: Mare::Compiler::Macros)
      end
    end
    
    it "complains if the number of terms is less than 2" do
      source = Mare::Source.new "(example)", <<-SOURCE
      actor Main:
        new:
          if True
      SOURCE
      
      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          if True
          ^~~~~~~
      - this term is the condition to be satisfied:
      from (example):3:
          if True
             ^~~~
      - expected a term: the body to be conditionally executed,
        including an optional else clause partitioned by `|`
      MSG
      
      expect_raises Mare::Compiler::Macros::Error, expected do
        Mare::Compiler.compile(source, limit: Mare::Compiler::Macros)
      end
    end
  end
end
