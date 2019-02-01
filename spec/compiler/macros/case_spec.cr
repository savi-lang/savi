describe Mare::Compiler::Macros do
  describe "case" do
    it "is transformed into a choice" do
      source = Mare::Source.new "(example)", <<-SOURCE
      actor Main:
        new:
          case (
          | x == 1 | "one"
          | x == 2 | "two"
          )
      SOURCE
      
      ctx = Mare::Compiler.compile([source], :macros)
      
      func = ctx.program.find_func!("Main", "new")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(", [:choice,
        [
          [:group, "(", [:relate, [:ident, "x"], [:op, "=="], [:integer, 1]]],
          [:group, "(", [:string, "one"]]
        ],
        [
          [:group, "(", [:relate, [:ident, "x"], [:op, "=="], [:integer, 2]]],
          [:group, "(", [:string, "two"]]
        ],
        [[:ident, "True"], [:ident, "None"]],
      ]]
    end
    
    it "with an odd number of sections treats the last one as an else clause" do
      source = Mare::Source.new "(example)", <<-SOURCE
      actor Main:
        new:
          case (
          | x == 1 | "one"
          | x == 2 | "two"
          | "three"
          )
      SOURCE
      
      ctx = Mare::Compiler.compile([source], :macros)
      
      func = ctx.program.find_func!("Main", "new")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(", [:choice,
        [
          [:group, "(", [:relate, [:ident, "x"], [:op, "=="], [:integer, 1]]],
          [:group, "(", [:string, "one"]]
        ],
        [
          [:group, "(", [:relate, [:ident, "x"], [:op, "=="], [:integer, 2]]],
          [:group, "(", [:string, "two"]]
        ],
        [[:ident, "True"], [:group, "(", [:string, "three"]]],
      ]]
    end
    
    it "can be written on one line, without the first pipe" do
      source = Mare::Source.new "(example)", <<-SOURCE
      actor Main:
        new:
          case (x == 1 | "one" | x == 2 | "two")
      SOURCE
      
      ctx = Mare::Compiler.compile([source], :macros)
      
      func = ctx.program.find_func!("Main", "new")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(", [:choice,
        [
          [:group, "(", [:relate, [:ident, "x"], [:op, "=="], [:integer, 1]]],
          [:group, "(", [:string, "one"]]
        ],
        [
          [:group, "(", [:relate, [:ident, "x"], [:op, "=="], [:integer, 2]]],
          [:group, "(", [:string, "two"]]
        ],
        [[:ident, "True"], [:ident, "None"]],
      ]]
    end
    
    it "complains if the number of top-level terms is more than one" do
      source = Mare::Source.new "(example)", <<-SOURCE
      actor Main:
        new:
          case (x == 1) "one" (x == 2) "two"
      SOURCE
      
      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          case (x == 1) "one" (x == 2) "two"
          ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      
      - this term is the group of cases to check, partitioned by `|`:
        from (example):3:
          case (x == 1) "one" (x == 2) "two"
               ^~~~~~~~
      
      - this is an excessive term:
        from (example):3:
          case (x == 1) "one" (x == 2) "two"
                         ^~~
      
      - this is an excessive term:
        from (example):3:
          case (x == 1) "one" (x == 2) "two"
                              ^~~~~~~~
      
      - this is an excessive term:
        from (example):3:
          case (x == 1) "one" (x == 2) "two"
                                        ^~~
      MSG
      
      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end
    
    it "complains if the term isn't a group" do
      source = Mare::Source.new "(example)", <<-SOURCE
      actor Main:
        new:
          case x == 1
      SOURCE
      
      expected = <<-MSG
      Expected this term to be a parenthesized group of cases to check,
        partitioned into sections by `|`, in which each body section
        is preceded by a condition section to be evaluated as a Bool,
        with an optional else body section at the end:
      from (example):3:
          case x == 1
               ^~~~~~
      MSG
      
      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end
    
    it "complains if the term isn't a pipe-delimited group" do
      source = Mare::Source.new "(example)", <<-SOURCE
      actor Main:
        new:
          case (x == 1)
      SOURCE
      
      expected = <<-MSG
      Expected this term to be a parenthesized group of cases to check,
        partitioned into sections by `|`, in which each body section
        is preceded by a condition section to be evaluated as a Bool,
        with an optional else body section at the end:
      from (example):3:
          case (x == 1)
               ^~~~~~~~
      MSG
      
      expect_raises Mare::Error, expected do
        Mare::Compiler.compile([source], :macros)
      end
    end
  end
end
