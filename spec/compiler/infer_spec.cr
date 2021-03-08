describe Mare::Compiler::Infer do
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "infers a local's type based on assignment" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = "Hello, World!"
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    infer = ctx.infer.for_func_simple(ctx, source, "Main", "new")
    body = infer.reified.func(ctx).body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)

    infer.analysis.resolved(ctx, assign.lhs).show_type.should eq "String"
    infer.analysis.resolved(ctx, assign.rhs).show_type.should eq "String"
  end

  it "infers a prop's type based on the prop initializer" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :prop x: "Hello, World!"
      :new
        @x
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    infer = ctx.infer.for_func_simple(ctx, source, "Main", "new")
    body = infer.reified.func(ctx).body.not_nil!
    prop = body.terms.first

    infer.analysis.resolved(ctx, prop).show_type.should eq "String"
  end

  it "infers an integer literal based on an assignment" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x (U64 | None) = 42
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    infer = ctx.infer.for_func_simple(ctx, source, "Main", "new")
    body = infer.reified.func(ctx).body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)

    infer.analysis.resolved(ctx, assign.lhs).show_type.should eq "(U64 | None)"
    infer.analysis.resolved(ctx, assign.rhs).show_type.should eq "U64"
  end

  it "infers an integer literal based on a prop type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :prop x (U64 | None): 42
      :new
        @x
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    main = ctx.namespace.main_type!(ctx)
    main_infer = ctx.infer.for_rt(ctx, main)
    func = main_infer.reified.defn(ctx).functions.find(&.has_tag?(:field)).not_nil!
    func_link = func.make_link(main)
    func_cap = Mare::Compiler::Infer::MetaType.cap(func.cap.value)
    infer = ctx.infer.for_rf(ctx, main_infer.reified, func_link, func_cap)
    body = infer.reified.func(ctx).body.not_nil!
    field = body.terms.first

    infer.analysis.resolved(ctx, field).show_type.should eq "U64"
  end

  it "infers an integer literal through an if statement" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x (U64 | String | None) = if True 42
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    infer = ctx.infer.for_func_simple(ctx, source, "Main", "new")
    body = infer.reified.func(ctx).body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    literal = assign.rhs
      .as(Mare::AST::Group).terms.last
      .as(Mare::AST::Choice).list[0][1]
      .as(Mare::AST::LiteralInteger)

    infer.analysis.resolved(ctx, assign.lhs).show_type.should eq "(U64 | String | None)"
    infer.analysis.resolved(ctx, assign.rhs).show_type.should eq "(U64 | None)"
    infer.analysis.resolved(ctx, literal).show_type.should eq "U64"
  end

  it "infers an integer literal within the else body of an if statement" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        u = U64[99]
        x = if True (u | 0)
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    infer = ctx.infer.for_func_simple(ctx, source, "Main", "new")
    body = infer.reified.func(ctx).body.not_nil!
    assign = body.terms[1].as(Mare::AST::Relate)
    literal = assign.rhs
      .as(Mare::AST::Group).terms.last
      .as(Mare::AST::Choice).list[1][1]
      .as(Mare::AST::Group).terms.last
      .as(Mare::AST::LiteralInteger)

    infer.analysis.resolved(ctx, assign.lhs).show_type.should eq "U64"
    infer.analysis.resolved(ctx, assign.rhs).show_type.should eq "U64"
    infer.analysis.resolved(ctx, literal).show_type.should eq "U64"
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    - and the literal itself has an intrinsic type of Numeric:
      from (example):6:
        | 0
          ^
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "infers return type from param type or another return type" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Infer
      :fun from_param (n I32): n
      :fun from_call_return (n I32): Infer.from_param(n)

    :actor Main
      :new
        Infer.from_call_return(42)
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    [
      {"Infer", "from_param"},
      {"Infer", "from_call_return"},
      {"Main", "new"},
    ].each do |t_name, f_name|
      infer = ctx.infer.for_func_simple(ctx, source, t_name, f_name)
      call = infer.reified.func(ctx).body.not_nil!.terms.first

      infer.analysis.resolved(ctx, call).show_type.should eq "I32"
    end
  end

  it "infers param type from local assignment or from the return type" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Infer
      :fun from_assign (n): m I32 = n
      :fun from_return_type (n) I32: n

    :actor Main
      :new
        Infer.from_assign(42)
        Infer.from_return_type(42)
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    [
      {"Infer", "from_assign"},
      {"Infer", "from_return_type"},
    ].each do |t_name, f_name|
      infer = ctx.infer.for_func_simple(ctx, source, t_name, f_name)
      expr = infer.reified.func(ctx).body.not_nil!.terms.first

      infer.analysis.resolved(ctx, expr).show_type.should eq "I32"
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
    This function body needs an explicit type; it could not be inferred:
    from (example):3:
      :fun dum (n I32): Tweedle.dee(n)
           ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "infers assignment from an allocated class" do
    source = Mare::Source.new_example <<-SOURCE
    :class X

    :actor Main
      :new
        x = X.new
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    infer = ctx.infer.for_func_simple(ctx, source, "Main", "new")
    body = infer.reified.func(ctx).body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)

    infer.analysis.resolved(ctx, assign.lhs).show_type.should eq "X"
    infer.analysis.resolved(ctx, assign.rhs).show_type.should eq "X"
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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
    The 'bar' function can't be called on (A | B | C):
    from (example):13:
        b.bar
          ^~~

    - C has no 'bar' function:
      from (example):7:
    :primitive C
               ^

    - maybe you meant to call the 'baz' function:
      from (example):8:
      :fun baz: "baz"
           ^~~

    - A has no 'bar' function:
      from (example):1:
    :trait A
           ^
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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
    The 'hello' function can't be called on Example:
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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
    The 'hello!' function can't be called on Example:
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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
    The 'hello' function can't be called on Example:
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when calling with an insufficient receiver capability" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Example
      :fun ref mutate

    :actor Main
      :new
        Example.mutate
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):6:
        Example.mutate
                ^~~~~~

    - the type Example isn't a subtype of the required capability of 'ref':
      from (example):2:
      :fun ref mutate
           ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains with an extra hint when using insufficient capability of @" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun ref mutate
      :fun readonly
        @mutate

    :actor Main
      :new
        Example.new.readonly
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):4:
        @mutate
         ^~~~~~

    - the type Example'box isn't a subtype of the required capability of 'ref':
      from (example):2:
      :fun ref mutate
           ^~~

    - this would be possible if the calling function were declared as `:fun ref`:
      from (example):3:
      :fun readonly
       ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when calling on a function with too many arguments" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
      :new
        @example(1, 2, 3)
        @example(1, 2, 3, 4)
        @example(1, 2, 3, 4, 5)
        @example(1, 2, 3, 4, 5, 6)
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):7:
        @example(1, 2, 3, 4, 5, 6)
         ^~~~~~~

    - the call site has too many arguments:
      from (example):7:
        @example(1, 2, 3, 4, 5, 6)
         ^~~~~~~

    - the function allows at most 5 arguments:
      from (example):2:
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when calling on a function with too few arguments" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
      :new
        @example(1, 2, 3, 4, 5)
        @example(1, 2, 3, 4)
        @example(1, 2, 3)
        @example(1, 2)
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):7:
        @example(1, 2)
         ^~~~~~~

    - the call site has too few arguments:
      from (example):7:
        @example(1, 2)
         ^~~~~~~

    - the function requires at least 3 arguments:
      from (example):2:
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when violating uniqueness into a local" do
    source = Mare::Source.new_example <<-SOURCE
    :class X
      :new iso

    :actor Main
      :new
        x1a iso = X.new
        x1b val = --x1a // okay

        x2a iso = X.new
        x2b iso = --x2a // okay
        x2c iso = --x2b // okay
        x2d val = --x2c // okay

        x3a iso = X.new
        x3b val = x3a // not okay
    SOURCE

    expected = <<-MSG
    This aliasing violates uniqueness (did you forget to consume the variable?):
    from (example):15:
        x3b val = x3a // not okay
                  ^~~

    - it is required here to be a subtype of val:
      from (example):15:
        x3b val = x3a // not okay
            ^~~

    - but the type of the local variable (when aliased) was X'tag:
      from (example):14:
        x3a iso = X.new
            ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "infers the type of an array literal from its elements" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = ["one", "two", "three"]
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    infer = ctx.infer.for_func_simple(ctx, source, "Main", "new")
    body = infer.reified.func(ctx).body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)

    infer.analysis.resolved(ctx, assign.lhs).show_type.should eq "Array(String)"
    infer.analysis.resolved(ctx, assign.rhs).show_type.should eq "Array(String)"
  end

  it "infers the element types of an array literal from an assignment" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x Array((U64 | None))'val = [1, 2, 3] // TODO: allow syntax: Array(U64 | None)'val?
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    infer = ctx.infer.for_func_simple(ctx, source, "Main", "new")
    body = infer.reified.func(ctx).body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    elem_0 = assign.rhs.as(Mare::AST::Group).terms.first

    infer.analysis.resolved(ctx, assign.lhs).show_type.should eq "Array((U64 | None))'val"
    infer.analysis.resolved(ctx, assign.rhs).show_type.should eq "Array((U64 | None))'val"
    infer.analysis.resolved(ctx, elem_0).show_type.should eq "U64"
  end

  it "complains when lifting the cap of an array with non-sendable elements" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        s String'ref = String.new
        array1 Array(String'ref)'val = [String.new_iso, String.new_iso]
        array2 Array(String'ref)'val = [s, s]
    SOURCE

    expected = <<-MSG
    This array literal can't have a reference cap of val unless all of its elements are sendable:
    from (example):5:
        array2 Array(String'ref)'val = [s, s]
                                       ^~~~~~

    - it is required here to be a subtype of Array(String'ref)'val:
      from (example):5:
        array2 Array(String'ref)'val = [s, s]
               ^~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "infers an empty array literal from its antecedent" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x Array(U64) = []
        x << 99
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    infer = ctx.infer.for_func_simple(ctx, source, "Main", "new")
    body = infer.reified.func(ctx).body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)

    infer.analysis.resolved(ctx, assign.lhs).show_type.should eq "Array(U64)"
    infer.analysis.resolved(ctx, assign.rhs).show_type.should eq "Array(U64)"
  end

  it "complains when an empty array literal has no antecedent" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = []
        x << 99
    SOURCE

    expected = <<-MSG
    The type of this empty array literal could not be inferred (it needs an explicit type):
    from (example):3:
        x = []
            ^~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when violating uniqueness into an array literal" do
    source = Mare::Source.new_example <<-SOURCE
    :class X
      :new iso

    :actor Main
      :new
        array_1 Array(X'val) = [X.new] // okay

        x2 iso = X.new
        array_2 Array(X'val) = [--x2] // okay

        x3 iso = X.new
        array_3 Array(X'tag) = [x3] // okay

        x4 iso = X.new
        array_4 Array(X'val) = [x4] // not okay
    SOURCE

    expected = <<-MSG
    This aliasing violates uniqueness (did you forget to consume the variable?):
    from (example):15:
        array_4 Array(X'val) = [x4] // not okay
                               ^~~~

    - it is required here to be a subtype of X'val:
      from (example):15:
        array_4 Array(X'val) = [x4] // not okay
                ^~~~~~~~~~~~

    - but the type of the local variable (when aliased) was X'tag:
      from (example):14:
        x4 iso = X.new
           ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when trying to implicitly recover an array literal" do
    source = Mare::Source.new_example <<-SOURCE
    :class X

    :actor Main
      :new
        x_ref X'ref = X.new
        array_ref ref = [x_ref] // okay
        array_box box = [x_ref] // okay
        array_val val = [x_ref] // not okay
    SOURCE

    # TODO: This error message will change when we have array literal recovery.
    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):8:
        array_val val = [x_ref] // not okay
                        ^~~~~~~

    - it is required here to be a subtype of val:
      from (example):8:
        array_val val = [x_ref] // not okay
                  ^~~

    - but the type of the array literal was Array(X):
      from (example):8:
        array_val val = [x_ref] // not okay
                        ^~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "reflects viewpoint adaptation in the return type of a prop getter" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner

    :class Outer
      :prop inner: Inner.new

    :actor Main
      :new
        outer_box Outer'box = Outer.new
        outer_ref Outer'ref = Outer.new

        inner_box1 Inner'box = outer_ref.inner // okay
        inner_ref1 Inner'ref = outer_ref.inner // okay
        inner_box2 Inner'box = outer_box.inner // okay
        inner_ref2 Inner'ref = outer_box.inner // not okay
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):14:
        inner_ref2 Inner'ref = outer_box.inner // not okay
                               ^~~~~~~~~~~~~~~

    - it is required here to be a subtype of Inner:
      from (example):14:
        inner_ref2 Inner'ref = outer_box.inner // not okay
                   ^~~~~~~~~

    - but the type of the return value was Inner'box:
      from (example):14:
        inner_ref2 Inner'ref = outer_box.inner // not okay
                                         ^~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "respects explicit viewpoint adaptation notation in the return type" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner

    :class Outer
      :prop inner: Inner.new
      :fun get_inner @->Inner: @inner

    :actor Main
      :new
        outer_box Outer'box = Outer.new
        outer_ref Outer'ref = Outer.new

        inner_box1 Inner'box = outer_ref.get_inner // okay
        inner_ref1 Inner'ref = outer_ref.get_inner // okay
        inner_box2 Inner'box = outer_box.get_inner // okay
        inner_ref2 Inner'ref = outer_box.get_inner // not okay
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):15:
        inner_ref2 Inner'ref = outer_box.get_inner // not okay
                               ^~~~~~~~~~~~~~~~~~~

    - it is required here to be a subtype of Inner:
      from (example):15:
        inner_ref2 Inner'ref = outer_box.get_inner // not okay
                   ^~~~~~~~~

    - but the type of the return value was Inner'box:
      from (example):15:
        inner_ref2 Inner'ref = outer_box.get_inner // not okay
                                         ^~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "treats box functions as being implicitly specialized on receiver cap" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner

    :class Outer
      :prop inner: Inner.new
      :new iso

    :actor Main
      :new
        outer_ref Outer'ref = Outer.new
        inner_ref Inner'ref = outer_ref.inner

        outer_val Outer'val = Outer.new
        inner_val Inner'val = outer_val.inner
    SOURCE

    Mare.compiler.compile([source], :infer)
  end

  it "allows safe auto-recovery of a property setter call" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner
      :new iso

    :class Outer
      :prop inner Inner: Inner.new
      :new iso

    :actor Main
      :new
        outer_iso Outer'iso = Outer.new
        inner_iso Inner'iso = Inner.new
        inner_ref Inner'ref = Inner.new

        outer_iso.inner = --inner_iso
        outer_iso.inner = inner_ref
    SOURCE

    expected = <<-MSG
    This function call won't work unless the receiver is ephemeral; it must either be consumed or be allowed to be auto-recovered. Auto-recovery didn't work for these reasons:
    from (example):15:
        outer_iso.inner = inner_ref
                  ^~~~~

    - the argument (when aliased) has a type of Inner, which isn't sendable:
      from (example):15:
        outer_iso.inner = inner_ref
                          ^~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "allows reading the value of a property getter function" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner
      :new iso

    :class Outer
      :prop inner_iso Inner'iso: Inner.new
      :prop inner_trn Inner'trn: Inner.new
      :prop inner_ref Inner'ref: Inner.new
      :prop inner_val Inner'val: Inner.new
      :prop inner_box Inner'box: Inner.new
      :prop inner_tag Inner'tag: Inner.new
      :new iso
      :new trn new_trn

    :actor Main
      :new
        outer_iso Outer'iso = Outer.new
        outer_trn Outer'trn = Outer.new
        outer_ref Outer'ref = Outer.new
        outer_val Outer'val = Outer.new
        outer_box Outer'box = Outer.new

        result_a1 Inner'iso = Outer.new.inner_iso
        result_a2 Inner'iso = Outer.new.inner_trn
        result_a3 Inner'iso = Outer.new.inner_ref
        result_a4 Inner'val = Outer.new.inner_val
        result_a5 Inner'val = Outer.new.inner_box
        result_a6 Inner'tag = Outer.new.inner_tag

        result_b1 Inner'iso'aliased = outer_iso.inner_iso
        result_b2 Inner'iso'aliased = outer_iso.inner_trn
        result_b3 Inner'iso'aliased = outer_iso.inner_ref
        result_b4 Inner'val = outer_iso.inner_val
        result_b5 Inner'tag = outer_iso.inner_box
        result_b6 Inner'tag = outer_iso.inner_tag

        result_c1 Inner'iso = Outer.new_trn.inner_iso
        result_c2 Inner'trn = Outer.new_trn.inner_trn
        result_c3 Inner'trn = Outer.new_trn.inner_ref
        result_c4 Inner'val = Outer.new_trn.inner_val
        result_c5 Inner'val = Outer.new_trn.inner_box
        result_c6 Inner'tag = Outer.new_trn.inner_tag

        result_d1 Inner'iso'aliased = outer_trn.inner_iso
        result_d2 Inner'trn'aliased = outer_trn.inner_trn
        result_d3 Inner'trn'aliased = outer_trn.inner_ref
        result_d4 Inner'val = outer_trn.inner_val
        result_d5 Inner'box = outer_trn.inner_box
        result_d6 Inner'tag = outer_trn.inner_tag

        result_e1 Inner'iso'aliased = outer_ref.inner_iso
        result_e2 Inner'trn'aliased = outer_ref.inner_trn
        result_e3 Inner'ref = outer_ref.inner_ref
        result_e4 Inner'val = outer_ref.inner_val
        result_e5 Inner'box = outer_ref.inner_box
        result_e6 Inner'tag = outer_ref.inner_tag

        result_f1 Inner'val = outer_val.inner_iso
        result_f2 Inner'val = outer_val.inner_trn
        result_f3 Inner'val = outer_val.inner_ref
        result_f4 Inner'val = outer_val.inner_val
        result_f5 Inner'val = outer_val.inner_box
        result_f6 Inner'tag = outer_val.inner_tag

        result_g1 Inner'tag = outer_box.inner_iso
        result_g2 Inner'box = outer_box.inner_trn
        result_g3 Inner'box = outer_box.inner_ref
        result_g4 Inner'val = outer_box.inner_val
        result_g5 Inner'box = outer_box.inner_box
        result_g6 Inner'tag = outer_box.inner_tag

        bad_example Inner'trn = outer_trn.inner_trn
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):71:
        bad_example Inner'trn = outer_trn.inner_trn
                                ^~~~~~~~~~~~~~~~~~~

    - it is required here to be a subtype of Inner'trn:
      from (example):71:
        bad_example Inner'trn = outer_trn.inner_trn
                    ^~~~~~~~~

    - but the type of the return value was Inner'box:
      from (example):71:
        bad_example Inner'trn = outer_trn.inner_trn
                                          ^~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "allows capturing the extracted value of a property replace function" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner
      :new iso

    :class Outer
      :prop inner_iso Inner'iso: Inner.new
      :prop inner_trn Inner'trn: Inner.new
      :prop inner_ref Inner'ref: Inner.new
      :prop inner_val Inner'val: Inner.new
      :prop inner_box Inner'box: Inner.new
      :prop inner_tag Inner'tag: Inner.new
      :new iso
      :new trn new_trn

    :actor Main
      :new
        outer_iso Outer'iso = Outer.new
        outer_trn Outer'trn = Outer.new
        outer_ref Outer'ref = Outer.new

        result_a1 Inner'iso = Outer.new.inner_iso <<= Inner.new
        result_a2 Inner'iso = Outer.new.inner_trn <<= Inner.new
        result_a3 Inner'iso = Outer.new.inner_ref <<= Inner.new
        result_a4 Inner'val = Outer.new.inner_val <<= Inner.new
        result_a5 Inner'val = Outer.new.inner_box <<= Inner.new
        result_a6 Inner'tag = Outer.new.inner_tag <<= Inner.new

        result_b1 Inner'iso = outer_iso.inner_iso <<= Inner.new
        result_b2 Inner'val = outer_iso.inner_trn <<= Inner.new
        result_b3 Inner'tag = outer_iso.inner_ref <<= Inner.new
        result_b4 Inner'val = outer_iso.inner_val <<= Inner.new
        result_b5 Inner'tag = outer_iso.inner_box <<= Inner.new
        result_b6 Inner'tag = outer_iso.inner_tag <<= Inner.new

        result_c1 Inner'iso = Outer.new_trn.inner_iso <<= Inner.new
        result_c2 Inner'trn = Outer.new_trn.inner_trn <<= Inner.new
        result_c3 Inner'trn = Outer.new_trn.inner_ref <<= Inner.new
        result_c4 Inner'val = Outer.new_trn.inner_val <<= Inner.new
        result_c5 Inner'val = Outer.new_trn.inner_box <<= Inner.new
        result_c6 Inner'tag = Outer.new_trn.inner_tag <<= Inner.new

        result_d1 Inner'iso = outer_trn.inner_iso <<= Inner.new
        result_d2 Inner'val = outer_trn.inner_trn <<= Inner.new
        result_d3 Inner'box = outer_trn.inner_ref <<= Inner.new
        result_d4 Inner'val = outer_trn.inner_val <<= Inner.new
        result_d5 Inner'box = outer_trn.inner_box <<= Inner.new
        result_d6 Inner'tag = outer_trn.inner_tag <<= Inner.new

        result_e1 Inner'iso = outer_ref.inner_iso <<= Inner.new
        result_e2 Inner'trn = outer_ref.inner_trn <<= Inner.new
        result_e3 Inner'ref = outer_ref.inner_ref <<= Inner.new
        result_e4 Inner'val = outer_ref.inner_val <<= Inner.new
        result_e5 Inner'box = outer_ref.inner_box <<= Inner.new
        result_e6 Inner'tag = outer_ref.inner_tag <<= Inner.new

        bad_example Inner'trn = outer_trn.inner_trn <<= Inner.new
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):55:
        bad_example Inner'trn = outer_trn.inner_trn <<= Inner.new
        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    - it is required here to be a subtype of Inner'trn:
      from (example):55:
        bad_example Inner'trn = outer_trn.inner_trn <<= Inner.new
                    ^~~~~~~~~

    - but the type of the return value was Inner'val:
      from (example):55:
        bad_example Inner'trn = outer_trn.inner_trn <<= Inner.new
                                          ^~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains on auto-recovery of a property setter whose return is used" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner
      :new iso

    :class Outer
      :prop inner Inner: Inner.new
      :new iso

    :actor Main
      :new
        outer_trn Outer'trn = Outer.new
        inner_2 = outer_trn.inner = Inner.new
    SOURCE

    expected = <<-MSG
    This function call won't work unless the receiver is ephemeral; it must either be consumed or be allowed to be auto-recovered. Auto-recovery didn't work for these reasons:
    from (example):11:
        inner_2 = outer_trn.inner = Inner.new
                            ^~~~~

    - the return type Inner isn't sendable and the return value is used (the return type wouldn't matter if the calling side entirely ignored the return value:
      from (example):5:
      :prop inner Inner: Inner.new
            ^~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains on auto-recovery for a val method receiver" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner
      :new iso

    :class Outer
      :prop inner Inner: Inner.new
      :fun val immutable Inner'val: @inner
      :new iso

    :actor Main
      :new
        outer Outer'iso = Outer.new
        inner Inner'val = outer.immutable
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):12:
        inner Inner'val = outer.immutable
                                ^~~~~~~~~

    - the function's receiver capability is `val` but only a `ref` or `box` receiver can be auto-recovered:
      from (example):6:
      :fun val immutable Inner'val: @inner
           ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "infers prop setters to return the alias of the assigned value" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner
      :new trn:

    :class Outer
      :prop inner Inner'trn: Inner.new

    :actor Main
      :new
        outer = Outer.new
        inner_box Inner'box = outer.inner = Inner.new // okay
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
    SOURCE

    # TODO: Fix position reporting that isn't quite right here:
    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):11:
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    - it is required here to be a subtype of Inner'trn:
      from (example):11:
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
                  ^~~~~~~~~

    - but the type of the return value was Inner'box:
      from (example):11:
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
                                    ^~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains if some params of an elevated constructor are not sendable" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :new val (a String'ref, b String'val, c String'box)
        None

    :actor Main
      :new
        Example.new(String.new, "", "")
    SOURCE

    expected = <<-MSG
    A constructor with elevated capability must only have sendable parameters:
    from (example):2:
      :new val (a String'ref, b String'val, c String'box)
           ^~~

    - this parameter type (String'ref) is not sendable:
      from (example):2:
      :new val (a String'ref, b String'val, c String'box)
                ^~~~~~~~~~~~

    - this parameter type (String'box) is not sendable:
      from (example):2:
      :new val (a String'ref, b String'val, c String'box)
                                            ^~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains if some params of an asynchronous function are not sendable" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Example
      :be call (a String'ref, b String'val, c String'box)
        None

    :actor Main
      :new
        Example.new.call(String.new, "", "")
    SOURCE

    expected = <<-MSG
    An asynchronous function must only have sendable parameters:
    from (example):2:
      :be call (a String'ref, b String'val, c String'box)
       ^~

    - this parameter type (String'ref) is not sendable:
      from (example):2:
      :be call (a String'ref, b String'val, c String'box)
                ^~~~~~~~~~~~

    - this parameter type (String'box) is not sendable:
      from (example):2:
      :be call (a String'ref, b String'val, c String'box)
                                            ^~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when a constant doesn't meet the expected type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
      :const i8 I8: 1
      :const u64 U64: 2
      :const f64 F32: 3.3
      :const str String: "Hello, World!"
      :const array_i8 Array(I8)'val: [1]
      :const array_u64 Array(U64)'val: [2]
      :const array_f32 Array(F32)'val: [3.3]
      :const array_str Array(String)'val: ["Hello", "World"]
      :const array_ref_str Array(String)'ref: ["Hello", "World"] // NOT VAL
    SOURCE

    expected = <<-MSG
    The type of a constant may only be String, a numeric type, or an immutable Array of one of these:
    from (example):11:
      :const array_ref_str Array(String)'ref: ["Hello", "World"] // NOT VAL
             ^~~~~~~~~~~~~

    - but the type is Array(String):
      from (example):11:
      :const array_ref_str Array(String)'ref: ["Hello", "World"] // NOT VAL
                           ^~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-func to be present in the subtype" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Trait
      :fun example1 U64
      :fun example2 U64
      :fun example3 U64

    :class Concrete
      :is Trait
      :fun example2 U64: 0

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):7:
      :is Trait
       ^~

    - this function isn't present in the subtype:
      from (example):2:
      :fun example1 U64
           ^~~~~~~~

    - this function isn't present in the subtype:
      from (example):4:
      :fun example3 U64
           ^~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-func to have the same constructor or constant tags" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Trait
      :new constructor1
      :new constructor2
      :new constructor3
      :const constant1 U64
      :const constant2 U64
      :const constant3 U64
      :fun function1 U64
      :fun function2 U64
      :fun function3 U64

    :class Concrete
      :is Trait
      :new constructor1
      :const constructor2 U64: 0
      :fun constructor3 U64: 0
      :new constant1
      :const constant2 U64: 0
      :fun constant3 U64: 0
      :new function1
      :const function2 U64: 0
      :fun function3 U64: 0

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):13:
      :is Trait
       ^~

    - a non-constructor can't be a subtype of a constructor:
      from (example):15:
      :const constructor2 U64: 0
             ^~~~~~~~~~~~

    - the constructor in the supertype is here:
      from (example):3:
      :new constructor2
           ^~~~~~~~~~~~

    - a non-constructor can't be a subtype of a constructor:
      from (example):16:
      :fun constructor3 U64: 0
           ^~~~~~~~~~~~

    - the constructor in the supertype is here:
      from (example):4:
      :new constructor3
           ^~~~~~~~~~~~

    - a constructor can't be a subtype of a non-constructor:
      from (example):17:
      :new constant1
           ^~~~~~~~~

    - the non-constructor in the supertype is here:
      from (example):5:
      :const constant1 U64
             ^~~~~~~~~

    - a non-constant can't be a subtype of a constant:
      from (example):19:
      :fun constant3 U64: 0
           ^~~~~~~~~

    - the constant in the supertype is here:
      from (example):7:
      :const constant3 U64
             ^~~~~~~~~

    - a constructor can't be a subtype of a non-constructor:
      from (example):20:
      :new function1
           ^~~~~~~~~

    - the non-constructor in the supertype is here:
      from (example):8:
      :fun function1 U64
           ^~~~~~~~~

    - a constant can't be a subtype of a non-constant:
      from (example):21:
      :const function2 U64: 0
             ^~~~~~~~~

    - the non-constant in the supertype is here:
      from (example):9:
      :fun function2 U64
           ^~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-func to have the same number of params" do
    source = Mare::Source.new_example <<-SOURCE
    :trait non Trait
      :fun example1 (a U64, b U64, c U64) None
      :fun example2 (a U64, b U64, c U64) None
      :fun example3 (a U64, b U64, c U64) None

    :primitive Concrete
      :is Trait
      :fun example1 None
      :fun example2 (a U64, b U64) None
      :fun example3 (a U64, b U64, c U64, d U64) None

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):7:
      :is Trait
       ^~

    - this function has too few parameters:
      from (example):8:
      :fun example1 None
           ^~~~~~~~

    - the supertype has 3 parameters:
      from (example):2:
      :fun example1 (a U64, b U64, c U64) None
                    ^~~~~~~~~~~~~~~~~~~~~

    - this function has too few parameters:
      from (example):9:
      :fun example2 (a U64, b U64) None
                    ^~~~~~~~~~~~~~

    - the supertype has 3 parameters:
      from (example):3:
      :fun example2 (a U64, b U64, c U64) None
                    ^~~~~~~~~~~~~~~~~~~~~

    - this function has too many parameters:
      from (example):10:
      :fun example3 (a U64, b U64, c U64, d U64) None
                    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~

    - the supertype has 3 parameters:
      from (example):4:
      :fun example3 (a U64, b U64, c U64) None
                    ^~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-constructor to have a covariant receiver capability" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Trait
      :new ref example1
      :new ref example2
      :new ref example3

    :class Concrete
      :is Trait
      :new box example1
      :new ref example2
      :new iso example3

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):7:
      :is Trait
       ^~

    - this constructor's receiver capability is box:
      from (example):8:
      :new box example1
           ^~~

    - it is required to be a subtype of ref:
      from (example):2:
      :new ref example1
           ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-func to have a contravariant receiver capability" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Trait
      :fun ref example1 U64
      :fun ref example2 U64
      :fun ref example3 U64

    :class Concrete
      :is Trait
      :fun box example1 U64: 0
      :fun ref example2 U64: 0
      :fun iso example3 U64: 0

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):7:
      :is Trait
       ^~

    - this function's receiver capability is iso:
      from (example):10:
      :fun iso example3 U64: 0
           ^~~

    - it is required to be a supertype of ref:
      from (example):4:
      :fun ref example3 U64
           ^~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "requires a sub-func to have covariant return and contravariant params" do
    source = Mare::Source.new_example <<-SOURCE
    :trait non Trait
      :fun example1 Numeric
      :fun example2 U64
      :fun example3 (a U64, b U64, c U64) None
      :fun example4 (a Numeric, b Numeric, c Numeric) None

    :primitive Concrete
      :is Trait
      :fun example1 U64: 0
      :fun example2 Numeric: U64[0]
      :fun example3 (a Numeric, b U64, c Numeric) None:
      :fun example4 (a U64, b Numeric, c U64) None:

    :actor Main
      :new
        Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):8:
      :is Trait
       ^~

    - this function's return type is Numeric:
      from (example):10:
      :fun example2 Numeric: U64[0]
                    ^~~~~~~

    - it is required to be a subtype of U64:
      from (example):3:
      :fun example2 U64
                    ^~~

    - this parameter type is U64:
      from (example):12:
      :fun example4 (a U64, b Numeric, c U64) None:
                     ^~~~~

    - it is required to be a supertype of Numeric:
      from (example):5:
      :fun example4 (a Numeric, b Numeric, c Numeric) None
                     ^~~~~~~~~

    - this parameter type is U64:
      from (example):12:
      :fun example4 (a U64, b Numeric, c U64) None:
                                       ^~~~~

    - it is required to be a supertype of Numeric:
      from (example):5:
      :fun example4 (a Numeric, b Numeric, c Numeric) None
                                           ^~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "prefers to show an error about assertions over other subtype failures" do
    source = Mare::Source.new_example <<-SOURCE
    :trait non Trait
      :fun example None

    :primitive Concrete
      :is Trait

    :actor Main
      :new
        x Trait = Concrete
    SOURCE

    expected = <<-MSG
    Concrete isn't a subtype of Trait, as it is required to be here:
    from (example):5:
      :is Trait
       ^~

    - this function isn't present in the subtype:
      from (example):2:
      :fun example None
           ^~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "allows assigning from a variable with its refined type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x val = "example"
        if (x <: String) (
          y String = x
        )
    SOURCE

    Mare.compiler.compile([source], :infer)
  end

  it "allows assigning from a parameter with its refined type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new: @refine("example")
      :fun refine (x val)
        if (x <: String) (
          y String = x
        )
    SOURCE

    Mare.compiler.compile([source], :infer)
  end

  it "complains when the match type isn't a subtype of the original" do
    source = Mare::Source.new_example <<-SOURCE
    :trait non Exampleable
      :fun non example String

    :actor Main
      :new: @refine("example")
      :fun refine (x String)
        if (x <: Exampleable) x.example
    SOURCE

    expected = <<-MSG
    This type check will never match:
    from (example):7:
        if (x <: Exampleable) x.example
            ^~~~~~~~~~~~~~~~

    - the runtime match type, ignoring capabilities, is Exampleable'any:
      from (example):7:
        if (x <: Exampleable) x.example
                 ^~~~~~~~~~~

    - which does not intersect at all with String:
      from (example):6:
      :fun refine (x String)
                     ^~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when a check would require runtime knowledge of capabilities" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new (env): @example("example")
      :fun example (x (String'val | String'ref))
        if (x <: String'ref) (
          x << "..."
        )
    SOURCE

    expected = <<-MSG
    This type check could violate capabilities:
    from (example):4:
        if (x <: String'ref) (
            ^~~~~~~~~~~~~~~

    - the runtime match type, ignoring capabilities, is String'any:
      from (example):4:
        if (x <: String'ref) (
                 ^~~~~~~~~~

    - if it successfully matches, the type will be (String | String'ref):
      from (example):3:
      :fun example (x (String'val | String'ref))
                      ^~~~~~~~~~~~~~~~~~~~~~~~~

    - which is not a subtype of String'ref:
      from (example):4:
        if (x <: String'ref) (
                 ^~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  pending "can also refine a type parameter within a choice body" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Sizeable
      :fun size USize

    :class Generic (A)
      :prop _value A
      :new (@_value)
      :fun ref value_size
        if (A <: Sizeable) (@_value.size)

    :actor Main
      :new
        Generic(String).new("example").value_size
    SOURCE

    Mare.compiler.compile([source], :infer)
  end

  it "complains when too many type arguments are provided" do
    source = Mare::Source.new_example <<-SOURCE
    :class Generic (P1, P2)

    :actor Main
      :new
        Generic(String, String, String, String)
    SOURCE

    expected = <<-MSG
    This type qualification has too many type arguments:
    from (example):5:
        Generic(String, String, String, String)
        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    - at most 2 type arguments were expected:
      from (example):1:
    :class Generic (P1, P2)
                   ^~~~~~~~

    - this is an excessive type argument:
      from (example):5:
        Generic(String, String, String, String)
                                ^~~~~~

    - this is an excessive type argument:
      from (example):5:
        Generic(String, String, String, String)
                                        ^~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when too few type arguments are provided" do
    source = Mare::Source.new_example <<-SOURCE
    :class Generic (P1, P2, P3)

    :actor Main
      :new
        Generic(String)
    SOURCE

    expected = <<-MSG
    This type qualification has too few type arguments:
    from (example):5:
        Generic(String)
        ^~~~~~~~~~~~~~~

    - at least 3 type arguments were expected:
      from (example):1:
    :class Generic (P1, P2, P3)
                   ^~~~~~~~~~~~

    - this additional type parameter needs an argument:
      from (example):1:
    :class Generic (P1, P2, P3)
                        ^~

    - this additional type parameter needs an argument:
      from (example):1:
    :class Generic (P1, P2, P3)
                            ^~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when no type arguments are provided and some are expected" do
    source = Mare::Source.new_example <<-SOURCE
    :class Generic (P1, P2)

    :actor Main
      :new
        Generic
    SOURCE

    expected = <<-MSG
    This type needs to be qualified with type arguments:
    from (example):5:
        Generic
        ^~~~~~~

    - these type parameters are expecting arguments:
      from (example):1:
    :class Generic (P1, P2)
                   ^~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when a type argument doesn't satisfy the bound" do
    source = Mare::Source.new_example <<-SOURCE
    :class Class
    :class Generic (P1 send)

    :actor Main
      :new
        Generic(Class)
    SOURCE

    expected = <<-MSG
    This type argument won't satisfy the type parameter bound:
    from (example):6:
        Generic(Class)
                ^~~~~

    - the type parameter bound is {iso, val, tag, non}:
      from (example):2:
    :class Generic (P1 send)
                       ^~~~

    - the type argument is Class:
      from (example):6:
        Generic(Class)
                ^~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "yields values to the caller" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun count_to (count U64) None
        :yields U64 for None
        i U64 = 0
        while (i < count) (
          i = i + 1
          yield i
        )
      :new
        sum U64 = 0
        @count_to(5) -> (i| sum = sum + i)
    SOURCE

    Mare.compiler.compile([source], :infer)
  end

  it "complains when a yield block is present on a non-yielding call" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun will_not_yield: None
      :new
        @will_not_yield -> (i| i)
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):4:
        @will_not_yield -> (i| i)
         ^~~~~~~~~~~~~~

    - it has a yield block but the called function does not have any yields:
      from (example):4:
        @will_not_yield -> (i| i)
                              ^~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when a yield block is not present on a yielding call" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun yield_99
        yield U64[99]
      :new
        @yield_99
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):5:
        @yield_99
         ^~~~~~~~

    - it has no yield block but the called function does yield:
      from (example):3:
        yield U64[99]
              ^~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  pending "complains when the yield param type doesn't match a constraint" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun yield_99
        yield U64[99]
      :new
        sum U32 = 0
        @yield_99 -> (i| j U32 = i)
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):6:
        @yield_99 -> (i| j U32 = i)
                                 ^

    - it is required here to be a subtype of U32:
      from (example):6:
        @yield_99 -> (i| j U32 = i)
                           ^~~

    - but the type of the value yielded to this block was U64:
      from (example):3:
        yield U64[99]
              ^~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "tests and conveys transitively reached subtypes to the reach pass" do
    source = Mare::Source.new_example <<-SOURCE
    :trait non Exampleable
      :fun non example String

    :primitive Example
      :fun non example String: "Hello, World!"

    :actor Main
      :fun maybe_call_example (e non)
        if (e <: Exampleable) e.example
      :new
        @maybe_call_example(Example)
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    any = ctx.namespace[source]["Any"].as(Mare::Program::Type::Link)
    trait = ctx.namespace[source]["Exampleable"].as(Mare::Program::Type::Link)
    sub = ctx.namespace[source]["Example"].as(Mare::Program::Type::Link)

    any_rt = ctx.infer[any].no_args
    trait_rt = ctx.infer[trait].no_args
    sub_rt = ctx.infer[sub].no_args

    mce_t, mce_f, mce_infer =
      ctx.infer.test_simple!(ctx, source, "Main", "maybe_call_example")
    e_param = mce_f.params.not_nil!.terms.first.not_nil!
    mce_infer.resolved(ctx, e_param).single!.should eq any_rt

    any_subtypes = ctx.infer[any_rt].each_known_complete_subtype(ctx).to_a
    trait_subtypes = ctx.infer[trait_rt].each_known_complete_subtype(ctx).to_a
    sub_subtypes = ctx.infer[sub_rt].each_known_complete_subtype(ctx).to_a

    any_subtypes.should contain(sub_rt)
    any_subtypes.should contain(trait_rt)
    trait_subtypes.should contain(sub_rt)
  end

  it "resolves all matching concrete reifications of abstract functions" do
    source = Mare::Source.new_example <<-SOURCE
    :class Person
      :fun greeting
        "Hello, World"

    :trait Greeter
      :fun greeting (String | None)

    :class World
      :fun meet! (greeter Greeter)
        greeter.greeting.as!(String)

    :actor Main
      :new (env)
        try env.out.print(World.new.meet!(Person.new))
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    t = ctx.namespace[source]["Person"].as(Mare::Program::Type::Link)
    rt = ctx.infer[t].no_args
    f = rt.defn(ctx).find_func!("greeting")
    f_link = f.make_link(rt.link)
    rfs = ctx.infer[f_link].each_reified_func(rt).to_a

    # Thanks to Infer#reach_additional_subtype_relationships, we expect that
    # both the box and ref reifications of this concrete function have been
    # reached, because ref is reached via the abstract Greeter'ref.greeting
    # (and box is reached always as part of normal type checking).
    rfs.map(&.receiver.cap_only.show_type).sort.should eq ["box", "ref"]
  end

  it "handles type-parameter-recursive type aliases" do
    source = Mare::Source.new_example <<-SOURCE
    :alias MyData (A Array'read): (String | U64 | A(MyData(A)))

    :actor Main
      :new (env)
        data MyData(Array'val) = ["Hello", "World", 99, ["Wow", [1, 2, 3]]]
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    t, f, infer = ctx.infer.test_simple!(ctx, source, "Main", "new")
    assign = f.body.not_nil!.terms.first.not_nil!.as(Mare::AST::Relate)
    l_type = assign.lhs.as(Mare::AST::Group).terms.last
    array1 = assign.rhs.as(Mare::AST::Group)
    array2 = array1.terms[3].as(Mare::AST::Group)
    array3 = array2.terms[1].as(Mare::AST::Group)

    expected_left_type = "(String | U64 | Array(MyData(Array'val))'val)"
    expected_right_type = "Array(MyData(Array'val))'val"

    infer.resolved(ctx, assign).show_type.should eq expected_left_type
    infer.resolved(ctx, l_type).show_type.should eq expected_left_type
    infer.resolved(ctx, array1).show_type.should eq expected_right_type
    infer.resolved(ctx, array2).show_type.should eq expected_right_type
    infer.resolved(ctx, array3).show_type.should eq expected_right_type
  end

  it "complains when a type-parameter is directly recursive" do
    source = Mare::Source.new_example <<-SOURCE
    :alias AdInfinitum: (String | U64 | AdInfinitum)

    :actor Main
      :new (env)
        data AdInfinitum = "Uh oh"
    SOURCE

    expected = <<-MSG
    This type alias is directly recursive, which is not supported:
    from (example):1:
    :alias AdInfinitum: (String | U64 | AdInfinitum)
           ^~~~~~~~~~~

    - only recursion via type arguments in this expression is supported:
      from (example):1:
    :alias AdInfinitum: (String | U64 | AdInfinitum)
                        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  pending "complains when the yield block result doesn't match the expected type"
  pending "enforces yield properties as part of trait subtyping"
end
