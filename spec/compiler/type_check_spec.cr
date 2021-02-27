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

  it "complains when a less specific type than required is assigned" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x (U64 | None) = 42
        y U64 = x
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):4:
        y U64 = x
                ^

    - it is required here to be a subtype of U64:
      from (example):4:
        y U64 = x
          ^~~

    - but the type of the local variable was (U64 | None):
      from (example):3:
        x (U64 | None) = 42
          ^~~~~~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when a different type is assigned on reassignment" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = U64[0]
        x = "a string"
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):4:
        x = "a string"
             ^~~~~~~~

    - it is required here to be a subtype of U64:
      from (example):3:
        x = U64[0]
        ^

    - but the type of the expression was String:
      from (example):4:
        x = "a string"
             ^~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "resolves return type from param type or another return type" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Infer
      :fun from_param (n I32): n
      :fun from_call_return (n I32): Infer.from_param(n)

    :actor Main
      :new
        Infer.from_call_return(42)
    SOURCE

    ctx = Mare.compiler.compile([source], :type_check)

    [
      {"Infer", "from_param"},
      {"Infer", "from_call_return"},
      {"Main", "new"},
    ].each do |t_name, f_name|
      type_check = ctx.type_check.for_func_simple(ctx, source, t_name, f_name)
      call = type_check.reified.func(ctx).body.not_nil!.terms.first

      type_check.analysis.resolved(ctx, call).show_type.should eq "I32"
    end
  end

  it "resolves param type from local assignment or from the return type" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Infer
      :fun from_assign (n): m I32 = n
      :fun from_return_type (n) I32: n

    :actor Main
      :new
        Infer.from_assign(42)
        Infer.from_return_type(42)
    SOURCE

    ctx = Mare.compiler.compile([source], :type_check)

    [
      {"Infer", "from_assign"},
      {"Infer", "from_return_type"},
    ].each do |t_name, f_name|
      type_check = ctx.type_check.for_func_simple(ctx, source, t_name, f_name)
      expr = type_check.reified.func(ctx).body.not_nil!.terms.first

      type_check.analysis.resolved(ctx, expr).show_type.should eq "I32"
    end
  end

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


  it "complains about problems with unreachable functions too" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive NeverCalled
      :fun call
        x I32 = True

    :actor Main
      :new
        None
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):3:
        x I32 = True
                ^~~~

    - it is required here to be a subtype of I32:
      from (example):3:
        x I32 = True
          ^~~

    - but the type of the expression was Bool:
      from (example):3:
        x I32 = True
                ^~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "resolves assignment from an allocated class" do
    source = Mare::Source.new_example <<-SOURCE
    :class X

    :actor Main
      :new
        x = X.new
    SOURCE

    ctx = Mare.compiler.compile([source], :type_check)

    type_check = ctx.type_check.for_func_simple(ctx, source, "Main", "new")
    body = type_check.reified.func(ctx).body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)

    type_check.analysis.resolved(ctx, assign.lhs).show_type.should eq "X"
    type_check.analysis.resolved(ctx, assign.rhs).show_type.should eq "X"
  end

  it "requires allocation for non-non references of an allocated class" do
    source = Mare::Source.new_example <<-SOURCE
    :class X

    :actor Main
      :new
        x X = X
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):5:
        x X = X
              ^

    - it is required here to be a subtype of X:
      from (example):5:
        x X = X
          ^

    - but the type of the singleton value for this type was X'non:
      from (example):5:
        x X = X
              ^
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when assigning with an insufficient right-hand capability" do
    source = Mare::Source.new_example <<-SOURCE
    :class C

    :actor Main
      :new
        c1 ref = C.new
        c2 C'iso = c1
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):6:
        c2 C'iso = c1
                   ^~

    - it is required here to be a subtype of C'iso:
      from (example):6:
        c2 C'iso = c1
           ^~~~~

    - but the type of the local variable was C:
      from (example):5:
        c1 ref = C.new
           ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when calling on types without that function" do
    source = Mare::Source.new_example <<-SOURCE
    :trait A
      :fun foo: "foo"

    :class B
      :fun bar: "bar"

    :primitive C
      :fun baz: "baz"

    :actor Main
      :new
        b (A | B | C) = B.new
        b.bar
    SOURCE

    expected = <<-MSG
    The 'bar' function can't be called on this local variable:
    from (example):13:
        b.bar
          ^~~

    - this local variable may have type C:
      from (example):12:
        b (A | B | C) = B.new
          ^~~~~~~~~~~

    - C has no 'bar' function:
      from (example):7:
    :primitive C
               ^

    - maybe you meant to call the 'baz' function:
      from (example):8:
      :fun baz: "baz"
           ^~~

    - this local variable may have type A:
      from (example):12:
        b (A | B | C) = B.new
          ^~~~~~~~~~~

    - A has no 'bar' function:
      from (example):1:
    :trait A
           ^
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "suggests a similarly named function when found" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Example
      :fun hey
      :fun hell
      :fun hello_world

    :actor Main
      :new
        Example.hello
    SOURCE

    expected = <<-MSG
    The 'hello' function can't be called on this singleton value for this type:
    from (example):8:
        Example.hello
                ^~~~~

    - Example has no 'hello' function:
      from (example):1:
    :primitive Example
               ^~~~~~~

    - maybe you meant to call the 'hell' function:
      from (example):3:
      :fun hell
           ^~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "suggests a similarly named function (without '!') when found" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Example
      :fun hello

    :actor Main
      :new
        Example.hello!
    SOURCE

    expected = <<-MSG
    The 'hello!' function can't be called on this singleton value for this type:
    from (example):6:
        Example.hello!
                ^~~~~~

    - Example has no 'hello!' function:
      from (example):1:
    :primitive Example
               ^~~~~~~

    - maybe you meant to call 'hello' (without '!'):
      from (example):2:
      :fun hello
           ^~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "suggests a similarly named function (with '!') when found" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Example
      :fun hello!

    :actor Main
      :new
        Example.hello
    SOURCE

    expected = <<-MSG
    The 'hello' function can't be called on this singleton value for this type:
    from (example):6:
        Example.hello
                ^~~~~

    - Example has no 'hello' function:
      from (example):1:
    :primitive Example
               ^~~~~~~

    - maybe you meant to call 'hello!' (with a '!'):
      from (example):2:
      :fun hello!
           ^~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  # ...

  it "complains when violating uniqueness into a reassigned local" do
    source = Mare::Source.new_example <<-SOURCE
    :class X
      :new iso

    :actor Main
      :new
        xb val = X.new // okay
        xb     = X.new // okay

        xa iso = X.new
        xb     = xa    // not okay
    SOURCE

    expected = <<-MSG
    This aliasing violates uniqueness (did you forget to consume the variable?):
    from (example):10:
        xb     = xa    // not okay
                 ^~

    - it is required here to be a subtype of val:
      from (example):6:
        xb val = X.new // okay
           ^~~

    - but the type of the local variable (when aliased) was X'tag:
      from (example):9:
        xa iso = X.new
           ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "allows extra aliases that don't violate uniqueness" do
    source = Mare::Source.new_example <<-SOURCE
    :class X
      :new iso

    :actor Main
      :new
        orig = X.new

        xa tag = orig   // okay
        xb tag = orig   // okay
        xc iso = --orig // okay
    SOURCE

    Mare.compiler.compile([source], :type_check)
  end

  it "complains when violating uniqueness into an argument" do
    source = Mare::Source.new_example <<-SOURCE
    :class X
      :new iso

    :actor Main
      :new
        @example(X.new) // okay

        x1 iso = X.new
        @example(--x1) // okay

        x2 iso = X.new
        @example(x2) // not okay

      :fun example (x X'val)
    SOURCE

    expected = <<-MSG
    This aliasing violates uniqueness (did you forget to consume the variable?):
    from (example):12:
        @example(x2) // not okay
                 ^~

    - it is required here to be a subtype of X'val:
      from (example):14:
      :fun example (x X'val)
                      ^~~~~

    - but the type of the local variable (when aliased) was X'tag:
      from (example):11:
        x2 iso = X.new
           ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "strips the ephemeral modifier from the capability of an inferred local" do
    source = Mare::Source.new_example <<-SOURCE
    :class X
      :new iso

    :actor Main
      :new
        x = X.new // inferred as X'iso+, stripped to X'iso
        x2 iso = x // not okay, but would work if not for the above stripping
        x3 iso = x // not okay, but would work if not for the above stripping
    SOURCE

    expected = <<-MSG
    This aliasing violates uniqueness (did you forget to consume the variable?):
    from (example):7:
        x2 iso = x // not okay, but would work if not for the above stripping
                 ^

    - it is required here to be a subtype of iso:
      from (example):7:
        x2 iso = x // not okay, but would work if not for the above stripping
           ^~~

    - it is required here to be a subtype of iso:
      from (example):8:
        x3 iso = x // not okay, but would work if not for the above stripping
           ^~~

    - but the type of the local variable (when aliased) was X'tag:
      from (example):6:
        x = X.new // inferred as X'iso+, stripped to X'iso
        ^
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  # ...
end
