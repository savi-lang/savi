describe Savi::Compiler::Macros do
  describe "error!" do
    it "is transformed into a jump" do
      source = Savi::Source.new_example <<-SOURCE
      :module Errors
        :fun example!
          error!
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Errors", "example!")
      func.body.not_nil!.terms.first.to_a.should eq \
        [:jump, "error", [:ident, "None"]]
    end

    it "can be used as an argument" do
      source = Savi::Source.new_example <<-SOURCE
      :module Errors
        :fun example!(cond)
          Some.method(error!)
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Errors", "example!")
      func.body.not_nil!.terms.first.to_a.should eq [:call,
        [:ident, "Some"],
        [:ident, "method"],
        [:group, "(", [:jump, "error", [:ident, "None"]]],
      ]
    end

    it "can be conditional with `if`" do
      source = Savi::Source.new_example <<-SOURCE
      :module Errors
        :fun example!(cond)
          error! if cond
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Errors", "example!")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(",
        [:choice,
          [[:ident, "cond"], [:jump, "error", [:ident, "None"]]],
          [[:ident, "True"], [:ident, "None"]],
        ],
      ]
    end

    it "complains if there are extra terms after the `if` condition" do
      source = Savi::Source.new_example <<-SOURCE
      :module Errors
        :fun example!(cond)
          error! if cond what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          error! if cond what now
          ^~~~~~~~~~~~~~~~~~~~~~~

      - this term is the condition that causes it to raise an error:
        from (example):3:
          error! if cond what now
                    ^~~~

      - this is an excessive term:
        from (example):3:
          error! if cond what now
                         ^~~~

      - this is an excessive term:
        from (example):3:
          error! if cond what now
                              ^~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is no `if` condition term" do
      source = Savi::Source.new_example <<-SOURCE
      :module Errors
        :fun example!(cond)
          error! if
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          error! if
          ^~~~~~~~~

      - expected a term: the condition that causes it to raise an error:
        from (example):3:
          error! if
          ^~~~~~~~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "can be conditional with `unless`" do
      source = Savi::Source.new_example <<-SOURCE
      :module Errors
        :fun example!(cond)
          error! unless cond
      SOURCE

      ctx = Savi.compiler.test_compile([source], :macros)
      ctx.errors.should be_empty

      func = ctx.namespace.find_func!(ctx, source, "Errors", "example!")
      func.body.not_nil!.terms.first.to_a.should eq [:group, "(",
        [:choice,
          [[:ident, "cond"], [:ident, "None"]],
          [[:ident, "True"], [:jump, "error", [:ident, "None"]]],
        ],
      ]
    end

    it "complains if there are extra terms after the `unless` condition" do
      source = Savi::Source.new_example <<-SOURCE
      :module Errors
        :fun example!(cond)
          error! unless cond what now
      SOURCE

      expected = <<-MSG
      This macro has too many terms:
      from (example):3:
          error! unless cond what now
          ^~~~~~~~~~~~~~~~~~~~~~~~~~~

      - this term is the condition that prevents it from raising an error:
        from (example):3:
          error! unless cond what now
                        ^~~~

      - this is an excessive term:
        from (example):3:
          error! unless cond what now
                             ^~~~

      - this is an excessive term:
        from (example):3:
          error! unless cond what now
                                  ^~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end

    it "complains if there is no `unless` condition term" do
      source = Savi::Source.new_example <<-SOURCE
      :module Errors
        :fun example!(cond)
          error! unless
      SOURCE

      expected = <<-MSG
      This macro has too few terms:
      from (example):3:
          error! unless
          ^~~~~~~~~~~~~

      - expected a term: the condition that prevents it from raising an error:
        from (example):3:
          error! unless
          ^~~~~~~~~~~~~
      MSG

      Savi.compiler.test_compile([source], :macros)
        .errors.map(&.message).join("\n").should eq expected
    end
  end
end
