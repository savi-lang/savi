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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
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
      Mare::Compiler.compile([source], :infer)
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
      Mare::Compiler.compile([source], :infer)
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
    
    - but the type of the literal value was String:
      from (example):3:
        "not a number at all"
         ^~~~~~~~~~~~~~~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
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
      Mare::Compiler.compile([source], :infer)
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
      Mare::Compiler.compile([source], :infer)
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
      Mare::Compiler.compile([source], :infer)
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
    
    - but the type of the literal value was String:
      from (example):3:
        if "not a boolean" 42
            ^~~~~~~~~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "infers a local's type based on assignment" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = "Hello, World!"
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    infer = ctx.infer.for_func_simple(ctx, "Main", "new")
    body = infer.reified.func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    
    infer.resolve(assign.lhs).show_type.should eq "String"
    infer.resolve(assign.rhs).show_type.should eq "String"
  end
  
  it "infers a prop's type based on the prop initializer" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :prop x: "Hello, World!"
      :new
        @x
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    infer = ctx.infer.for_func_simple(ctx, "Main", "new")
    body = infer.reified.func.body.not_nil!
    prop = body.terms.first
    
    infer.resolve(prop).show_type.should eq "String"
  end
  
  it "infers an integer literal based on an assignment" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x (U64 | None) = 42
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    infer = ctx.infer.for_func_simple(ctx, "Main", "new")
    body = infer.reified.func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    
    infer.resolve(assign.lhs).show_type.should eq "(U64 | None)"
    infer.resolve(assign.rhs).show_type.should eq "U64"
  end
  
  it "infers an integer literal based on a prop type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :prop x (U64 | None): 42
      :new
        @x
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    main = ctx.namespace["Main"].as(Mare::Program::Type)
    main_infer = ctx.infer.for_type(ctx, main)
    func = main_infer.reified.defn.functions.find(&.has_tag?(:field)).not_nil!
    func_cap = Mare::Compiler::Infer::MetaType.cap(func.cap.value)
    infer = ctx.infer.for_func(ctx, main_infer.reified, func, func_cap)
    body = infer.reified.func.body.not_nil!
    field = body.terms.first
    
    infer.resolve(field).show_type.should eq "U64"
  end
  
  it "infers an integer literal through an if statement" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x (U64 | String | None) = if True 42
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    infer = ctx.infer.for_func_simple(ctx, "Main", "new")
    body = infer.reified.func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    literal = assign.rhs
      .as(Mare::AST::Group).terms.last
      .as(Mare::AST::Choice).list[0][1]
      .as(Mare::AST::LiteralInteger)
    
    infer.resolve(assign.lhs).show_type.should eq "(U64 | String | None)"
    infer.resolve(assign.rhs).show_type.should eq "(U64 | None)"
    infer.resolve(literal).show_type.should eq "U64"
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
    
    - and the literal itself has an intrinsic type of (F64 | U64):
      from (example):3:
        x (F64 | U64) = 42
                        ^~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
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
      Mare::Compiler.compile([source], :infer)
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
    
    - but the type of the literal value was String:
      from (example):4:
        x = "a string"
             ^~~~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    [
      {"Infer", "from_param"},
      {"Infer", "from_call_return"},
      {"Main", "new"},
    ].each do |t_name, f_name|
      infer = ctx.infer.for_func_simple(ctx, t_name, f_name)
      call = infer.reified.func.body.not_nil!.terms.first
      
      infer.resolve(call).show_type.should eq "I32"
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
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    [
      {"Infer", "from_assign"},
      {"Infer", "from_return_type"},
    ].each do |t_name, f_name|
      infer = ctx.infer.for_func_simple(ctx, t_name, f_name)
      expr = infer.reified.func.body.not_nil!.terms.first
      
      infer.resolve(expr).show_type.should eq "I32"
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
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
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "infers assignment from an allocated class" do
    source = Mare::Source.new_example <<-SOURCE
    :class X
    
    :actor Main
      :new
        x = X.new
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    infer = ctx.infer.for_func_simple(ctx, "Main", "new")
    body = infer.reified.func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    
    infer.resolve(assign.lhs).show_type.should eq "X"
    infer.resolve(assign.rhs).show_type.should eq "X"
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
    
    - but the type of the expression was X'non:
      from (example):5:
        x X = X
              ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
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
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "complains when calling on types without that function" do
    source = Mare::Source.new_example <<-SOURCE
    :trait A
      :fun foo
    
    :primitive B
      :fun bar
    
    :class C
      :fun baz
    
    :actor Main
      :new
        c (A | B | C) = C.new
        c.baz
    SOURCE
    
    expected = <<-MSG
    The 'baz' function can't be called on (A | B | C):
    from (example):13:
        c.baz
          ^~~
    
    - A has no 'baz' function:
      from (example):1:
    :trait A
           ^
    
    - B has no 'baz' function:
      from (example):4:
    :primitive B
               ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    The type of this expression doesn't meet the constraints imposed on it:
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
    
    - this would be allowed if this reference didn't get aliased
    - did you forget to consume the reference?
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):10:
        xb     = xa    // not okay
                 ^~
    
    - it is required here to be a subtype of X'val:
      from (example):6:
        xb val = X.new // okay
           ^~~
    
    - but the type of the local variable (when aliased) was X'tag:
      from (example):9:
        xa iso = X.new
           ^~~
    
    - this would be allowed if this reference didn't get aliased
    - did you forget to consume the reference?
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    The type of this expression doesn't meet the constraints imposed on it:
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
    
    - this would be allowed if this reference didn't get aliased
    - did you forget to consume the reference?
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
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
    The type of this expression doesn't meet the constraints imposed on it:
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
    
    - but the type of the return value (when aliased) was X'tag:
      from (example):6:
        x = X.new // inferred as X'iso+, stripped to X'iso
              ^~~
    
    - this would be allowed if this reference didn't get aliased
    - did you forget to consume the reference?
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "infers the type of an array literal from its elements" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = ["one", "two", "three"]
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    infer = ctx.infer.for_func_simple(ctx, "Main", "new")
    body = infer.reified.func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    
    infer.resolve(assign.lhs).show_type.should eq "Array(String)"
    infer.resolve(assign.rhs).show_type.should eq "Array(String)"
  end
  
  it "infers the element types of an array literal from an assignment" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x Array((U64 | None)) = [1, 2, 3] // TODO: allow syntax: Array(U64 | None)?
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    infer = ctx.infer.for_func_simple(ctx, "Main", "new")
    body = infer.reified.func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    elem_0 = assign.rhs.as(Mare::AST::Group).terms.first
    
    infer.resolve(assign.lhs).show_type.should eq "Array((U64 | None))"
    infer.resolve(assign.rhs).show_type.should eq "Array((U64 | None))"
    infer.resolve(elem_0).show_type.should eq "U64"
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
    The type of this expression doesn't meet the constraints imposed on it:
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
    
    - this would be allowed if this reference didn't get aliased
    - did you forget to consume the reference?
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    Mare::Compiler.compile([source], :infer)
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    This function call won't work unless the receiver is ephemeral; it must either be consumed or be allowed to be auto-recovered. Auto-recovery didn't work for these reasons:
    from (example):12:
        inner Inner'val = outer.immutable
                                ^~~~~~~~~
    
    - the function's receiver capability is `val` but only a `ref` or `box` receiver can be auto-recovered:
      from (example):6:
      :fun val immutable Inner'val: @inner
           ^~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  pending "requires parameters of 'recovered' constructors to be sendable"
  
  pending "requires parameters of actor behaviours to be sendable"
  
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    - 2 type arguments were expected:
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    - 3 type arguments were expected:
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
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
    
    - the type parameter bound is here:
      from (example):2:
    :class Generic (P1 send)
                       ^~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
end
