describe Mare::Compiler::TypeCheck do
  it "complains when the type identifier couldn't be resolved" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x BogusType = 42
    SOURCE

    expected = <<-MSG
    This type couldn't be resolved:
    from (example):3:
        x BogusType = 42
          ^~~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when the return type identifier couldn't be resolved" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun x BogusType: 42
      :new
        @x
    SOURCE

    expected = <<-MSG
    This type couldn't be resolved:
    from (example):2:
      :fun x BogusType: 42
             ^~~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when the local identifier couldn't be resolved" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = y
    SOURCE

    expected = <<-MSG
    This identifer couldn't be resolved:
    from (example):3:
        x = y
            ^
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when a local identifier wasn't declared, even when unused" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        bogus
    SOURCE

    expected = <<-MSG
    This identifer couldn't be resolved:
    from (example):3:
        bogus
        ^~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when the function body doesn't match the return type" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Example
      :fun number I32
        "not a number at all"

    :actor Main
      :new
        Example.number
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):3:
        "not a number at all"
         ^~~~~~~~~~~~~~~~~~~

    - it is required here to be a subtype of I32:
      from (example):2:
      :fun number I32
                  ^~~

    - but the type of the expression was String:
      from (example):3:
        "not a number at all"
         ^~~~~~~~~~~~~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when the assignment type doesn't match the right-hand-side" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        name String = 42
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):3:
        name String = 42
                      ^~

    - it is required here to be a subtype of String:
      from (example):3:
        name String = 42
             ^~~~~~

    - but the type of the literal value was Numeric:
      from (example):3:
        name String = 42
                      ^~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when the prop type doesn't match the initializer value" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :prop name String: 42
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):2:
      :prop name String: 42
                         ^~

    - it is required here to be a subtype of String:
      from (example):2:
      :prop name String: 42
                 ^~~~~~

    - but the type of the literal value was Numeric:
      from (example):2:
      :prop name String: 42
                         ^~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "treats an empty sequence as producing None" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        name String = ()
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):3:
        name String = ()
                      ^~

    - it is required here to be a subtype of String:
      from (example):3:
        name String = ()
             ^~~~~~

    - but the type of the expression was None:
      from (example):3:
        name String = ()
                      ^~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when a choice condition type isn't boolean" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        if "not a boolean" 42
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):3:
        if "not a boolean" 42
        ^~

    - it is required here to be a subtype of Bool:
      from (example):3:
        if "not a boolean" 42
        ^~

    - but the type of the expression was String:
      from (example):3:
        if "not a boolean" 42
            ^~~~~~~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  pending "complains when a loop's implicit '| None' result doesn't pass checks" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new(env Env)
        i USize = 0

        result = while (i < 2) (i += 1
          "This loop ran at least once"
        )

        env.out.print(result)
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):5:
        result = while (i < 2) (i += 1
                 ^~~~~

    - it is required here to be a subtype of String:
      from (example):9:
        env.out.print(result)
                      ^~~~~~

    - but the type of the loop's result when it runs zero times was None:
      from (example):5:
        result = while (i < 2) (i += 1
                 ^~~~~~~~~~~~~~~~~~~~~···
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "resolves a local's type based on assignment" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = "Hello, World!"
    SOURCE

    ctx = Mare.compiler.compile([source], :type_check)

    type_check = ctx.type_check.for_func_simple(ctx, source, "Main", "new")
    body = type_check.reified.func(ctx).body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)

    type_check.analysis.resolved(ctx, assign.lhs).show_type.should eq "String"
    type_check.analysis.resolved(ctx, assign.rhs).show_type.should eq "String"
  end

  it "resolves a prop's type based on the prop initializer" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :prop x: "Hello, World!"
      :new
        @x
    SOURCE

    ctx = Mare.compiler.compile([source], :type_check)

    type_check = ctx.type_check.for_func_simple(ctx, source, "Main", "new")
    body = type_check.reified.func(ctx).body.not_nil!
    prop = body.terms.first

    type_check.analysis.resolved(ctx, prop).show_type.should eq "String"
  end

  it "resolves an integer literal based on an assignment" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x (U64 | None) = 42
    SOURCE

    ctx = Mare.compiler.compile([source], :type_check)

    type_check = ctx.type_check.for_func_simple(ctx, source, "Main", "new")
    body = type_check.reified.func(ctx).body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)

    type_check.analysis.resolved(ctx, assign.lhs).show_type.should eq "(U64 | None)"
    type_check.analysis.resolved(ctx, assign.rhs).show_type.should eq "U64"
  end

  it "resolves an integer literal based on a prop type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :prop x (U64 | None): 42
      :new
        @x
    SOURCE

    ctx = Mare.compiler.compile([source], :type_check)

    main = ctx.namespace.main_type!(ctx)
    main_type_check = ctx.type_check.for_rt(ctx, main)
    func = main_type_check.reified.defn(ctx).functions.find(&.has_tag?(:field)).not_nil!
    func_link = func.make_link(main)
    func_cap = Mare::Compiler::Infer::MetaType.cap(func.cap.value)
    type_check = ctx.type_check.for_rf(ctx, main_type_check.reified, func_link, func_cap)
    body = type_check.reified.func(ctx).body.not_nil!
    field = body.terms.first

    type_check.analysis.resolved(ctx, field).show_type.should eq "U64"
  end

  it "resolves an integer literal through an if statement" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x (U64 | String | None) = if True 42
    SOURCE

    ctx = Mare.compiler.compile([source], :type_check)

    type_check = ctx.type_check.for_func_simple(ctx, source, "Main", "new")
    body = type_check.reified.func(ctx).body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    literal = assign.rhs
      .as(Mare::AST::Group).terms.last
      .as(Mare::AST::Choice).list[0][1]
      .as(Mare::AST::LiteralInteger)

    type_check.analysis.resolved(ctx, assign.lhs).show_type.should eq "(U64 | String | None)"
    type_check.analysis.resolved(ctx, assign.rhs).show_type.should eq "(U64 | None)"
    type_check.analysis.resolved(ctx, literal).show_type.should eq "U64"
  end

  it "resolves an integer literal within the else body of an if statement" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        u = U64[99]
        x = if True (u | 0)
    SOURCE

    ctx = Mare.compiler.compile([source], :type_check)

    type_check = ctx.type_check.for_func_simple(ctx, source, "Main", "new")
    body = type_check.reified.func(ctx).body.not_nil!
    assign = body.terms[1].as(Mare::AST::Relate)
    literal = assign.rhs
      .as(Mare::AST::Group).terms.last
      .as(Mare::AST::Choice).list[1][1]
      .as(Mare::AST::Group).terms.last
      .as(Mare::AST::LiteralInteger)

    type_check.analysis.resolved(ctx, assign.lhs).show_type.should eq "U64"
    type_check.analysis.resolved(ctx, assign.rhs).show_type.should eq "U64"
    type_check.analysis.resolved(ctx, literal).show_type.should eq "U64"
  end

  it "complains when a literal couldn't be resolved to a single type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x (F64 | U64) = 42
    SOURCE

    expected = <<-MSG
    This literal value couldn't be inferred as a single concrete type:
    from (example):3:
        x (F64 | U64) = 42
                        ^~

    - it is required here to be a subtype of (F64 | U64):
      from (example):3:
        x (F64 | U64) = 42
          ^~~~~~~~~~~

    - and the literal itself has an intrinsic type of Numeric:
      from (example):3:
        x (F64 | U64) = 42
                        ^~

    - Please wrap an explicit numeric type around the literal (for example: U64[42])
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when literal couldn't resolve even when calling u64 method" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = 42.u64
    SOURCE

    expected = <<-MSG
    This literal value couldn't be inferred as a single concrete type:
    from (example):3:
        x = 42.u64
            ^~

    - and the literal itself has an intrinsic type of Numeric:
      from (example):3:
        x = 42.u64
            ^~

    - Please wrap an explicit numeric type around the literal (for example: U64[42])
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when literal couldn't resolve and had conflicting hints" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun non example (string String)
        case (
        | string.size < 10 | U64[99]
        | string.size > 90 | I64[88]
        | 0
        )
      :new
        @example("Hello, World!")
    SOURCE

    expected = <<-MSG
    This literal value couldn't be inferred as a single concrete type:
    from (example):6:
        | 0
          ^

    - it is suggested here that it might be a U64:
      from (example):4:
        | string.size < 10 | U64[99]
                                ^~~~

    - it is suggested here that it might be a I64:
      from (example):5:
        | string.size > 90 | I64[88]
                                ^~~~

    - it is required here to be a subtype of (U64 | I64):
      from (example):3:
        case (
        ^~~~~~···

    - and the literal itself has an intrinsic type of Numeric:
      from (example):6:
        | 0
          ^

    - Please wrap an explicit numeric type around the literal (for example: U64[0])
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  # ...

  it "complains when unable to infer mutually recursive return types" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Tweedle
      :fun dee (n I32): Tweedle.dum(n)
      :fun dum (n I32): Tweedle.dee(n)

    :actor Main
      :new
        Tweedle.dum(42)
    SOURCE

    expected = <<-MSG
    This return value needs an explicit type; it could not be inferred:
    from (example):3:
      :fun dum (n I32): Tweedle.dee(n)
                                ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  # ...
end
