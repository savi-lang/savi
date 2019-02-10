describe Mare::Compiler::Infer do
  it "complains when the type identifier couldn't be resolved" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
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
  
  it "complains when the local identifier couldn't be resolved" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
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
    source = Mare::Source.new "(example)", <<-SOURCE
    primitive Example:
      fun number I32:
        "not a number at all"
    
    actor Main:
      new:
        Example.number
    SOURCE
    
    expected = <<-MSG
    This value's type is unresolvable due to conflicting constraints:
    from (example):3:
        "not a number at all"
         ^~~~~~~~~~~~~~~~~~~
    
    - it must be a subtype of String:
      from (example):3:
        "not a number at all"
         ^~~~~~~~~~~~~~~~~~~
    
    - it must be a subtype of I32:
      from (example):2:
      fun number I32:
                 ^~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "complains when the assignment type doesn't match the right-hand-side" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        name String = 42
    SOURCE
    
    expected = <<-MSG
    This value's type is unresolvable due to conflicting constraints:
    from (example):3:
        name String = 42
                      ^~

    - it must be a subtype of Numeric:
      from (example):3:
        name String = 42
                      ^~
    
    - it must be a subtype of String:
      from (example):3:
        name String = 42
             ^~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "complains when the prop type doesn't match the initializer value" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      prop name String: 42
    SOURCE
    
    expected = <<-MSG
    This value's type is unresolvable due to conflicting constraints:
    from (example):2:
      prop name String: 42
                        ^~
    
    - it must be a subtype of Numeric:
      from (example):2:
      prop name String: 42
                        ^~
    
    - it must be a subtype of String:
      from (example):2:
      prop name String: 42
                ^~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "treats an empty sequence as producing None" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        name String = ()
    SOURCE
    
    expected = <<-MSG
    This type is outside of a constraint: None:
    from (example):3:
        name String = ()
                      ^~
    
    - it must be a subtype of String:
      from (example):3:
        name String = ()
             ^~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "complains when a choice condition type isn't boolean" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        if "not a boolean" 42
    SOURCE
    
    expected = <<-MSG
    This value's type is unresolvable due to conflicting constraints:
    from (example):3:
        if "not a boolean" 42
            ^~~~~~~~~~~~~
    
    - it must be a subtype of String:
      from (example):3:
        if "not a boolean" 42
            ^~~~~~~~~~~~~
    
    - it must be a subtype of Bool:
      from (example):3:
        if "not a boolean" 42
        ^~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "infers a local's type based on assignment" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        x = "Hello, World!"
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    func = ctx.program.find_func!("Main", "new")
    body = func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    
    func.infer.resolve(assign.lhs).show_type.should eq "String"
    func.infer.resolve(assign.rhs).show_type.should eq "String"
  end
  
  it "infers a prop's type based on the prop initializer" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      prop x: "Hello, World!"
      new:
        @x
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    func = ctx.program.find_func!("Main", "new")
    body = func.body.not_nil!
    prop = body.terms.first
    
    func.infer.resolve(prop).show_type.should eq "String"
  end
  
  it "infers an integer literal based on an assignment" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        x (U64 | None) = 42
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    func = ctx.program.find_func!("Main", "new")
    body = func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    
    func.infer.resolve(assign.lhs).show_type.should eq "(U64 | None)"
    func.infer.resolve(assign.rhs).show_type.should eq "U64"
  end
  
  it "infers an integer literal based on a prop type" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      prop x U64: 42 // TODO: test with (U64 | None) when it works
      new:
        @x
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    func = ctx.program.find_func!("Main", "new")
    body = func.body.not_nil!
    prop = body.terms.first
    
    func.infer.resolve(prop).show_type.should eq "U64"
  end
  
  it "infers an integer literal through an if statement" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        x (U64 | String | None) = if True 42
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    func = ctx.program.find_func!("Main", "new")
    body = func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    literal = assign.rhs
      .as(Mare::AST::Group).terms.last
      .as(Mare::AST::Choice).list[0][1]
      .as(Mare::AST::LiteralInteger)
    
    func.infer.resolve(assign.lhs).show_type.should eq "(U64 | String | None)"
    func.infer.resolve(assign.rhs).show_type.should eq "(U64 | None)"
    func.infer.resolve(literal).show_type.should eq "U64"
  end
  
  it "complains when a literal couldn't be resolved to a single type" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        x (F64 | U64) = 42
    SOURCE
    
    expected = <<-MSG
    This value couldn't be inferred as a single concrete type:
    from (example):3:
        x (F64 | U64) = 42
                        ^~
    
    - it must be a subtype of Numeric:
      from (example):3:
        x (F64 | U64) = 42
                        ^~
    
    - it must be a subtype of (F64 | U64):
      from (example):3:
        x (F64 | U64) = 42
          ^~~~~~~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "complains when a less specific type than required is assigned" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        x (U64 | None) = 42
        y U64 = x
    SOURCE
    
    expected = <<-MSG
    This type is outside of a constraint: (U64 | None):
    from (example):3:
        x (U64 | None) = 42
        ^
    
    - it must be a subtype of U64:
      from (example):4:
        y U64 = x
          ^~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "infers return type from param type or another return type" do
    source = Mare::Source.new "(example)", <<-SOURCE
    primitive Infer:
      fun from_param (n I32): n
      fun from_call_return (n I32): Infer.from_param(n)
    
    actor Main:
      new:
        Infer.from_call_return(42)
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    [
      {"Infer", "from_param"},
      {"Infer", "from_call_return"},
      {"Main", "new"},
    ].each do |t_name, f_name|
      func = ctx.program.find_func!(t_name, f_name)
      call = func.body.not_nil!.terms.first
      
      func.infer.resolve(call).show_type.should eq "I32"
    end
  end
  
  it "infers param type from local assignment or from the return type" do
    source = Mare::Source.new "(example)", <<-SOURCE
    primitive Infer:
      fun from_assign (n): m I32 = n
      fun from_return_type (n) I32: n
    
    actor Main:
      new:
        Infer.from_assign(42)
        Infer.from_return_type(42)
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    [
      {"Infer", "from_assign"},
      {"Infer", "from_return_type"},
    ].each do |t_name, f_name|
      func = ctx.program.find_func!(t_name, f_name)
      expr = func.body.not_nil!.terms.first
      
      func.infer.resolve(expr).show_type.should eq "I32"
    end
  end
  
  it "complains when unable to infer mutually recursive return types" do
    source = Mare::Source.new "(example)", <<-SOURCE
    primitive Tweedle:
      fun dee (n I32): Tweedle.dum(n)
      fun dum (n I32): Tweedle.dee(n)
    
    actor Main:
      new:
        Tweedle.dum(42)
    SOURCE
    
    expected = <<-MSG
    This needs an explicit type; it could not be inferred:
    from (example):3:
      fun dum (n I32): Tweedle.dee(n)
          ^~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "allows an interface to be fulfilled with a covariant return type" do
    source = Mare::Source.new "(example)", <<-SOURCE
    interface non Interface:
      fun example Interface:
    
    primitive Concrete:
      is Interface:
      fun example Concrete: Concrete
    
    actor Main:
      new:
        Concrete
    SOURCE
    
    Mare::Compiler.compile([source], :infer)
  end
  
  it "complains when an interface has a covariant argument type" do
    source = Mare::Source.new "(example)", <<-SOURCE
    interface non Interface:
      fun example (arg Interface) None:
    
    primitive Concrete:
      is Interface:
      fun example (arg Concrete) None: None
    
    actor Main:
      new:
        Concrete
    SOURCE
    
    expected = <<-MSG
    This type isn't a subtype of Interface:
    from (example):4:
    primitive Concrete:
              ^~~~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "complains about problems with unreachable functions too" do
    source = Mare::Source.new "(example)", <<-SOURCE
    primitive NeverCalled:
      fun call:
        x I32 = True
    
    actor Main:
      new:
        None
    SOURCE
    
    expected = <<-MSG
    This type is outside of a constraint: Bool:
    from (example):3:
        x I32 = True
                ^~~~
    
    - it must be a subtype of I32:
      from (example):3:
        x I32 = True
          ^~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "infers assignment from an allocated class" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class X:
    
    actor Main:
      new:
        x = X.new
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    func = ctx.program.find_func!("Main", "new")
    body = func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    
    func.infer.resolve(assign.lhs).show_type.should eq "X"
    func.infer.resolve(assign.rhs).show_type.should eq "X"
  end
  
  it "requires allocation for non-non references of an allocated class" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class X:
    
    actor Main:
      new:
        x X = X
    SOURCE
    
    expected = <<-MSG
    This type is outside of a constraint: X'non:
    from (example):5:
        x X = X
              ^
    
    - it must be a subtype of X:
      from (example):5:
        x X = X
          ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "complains when assigning with an insufficient right-hand capability" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class C:
    
    actor Main:
      new:
        c1 C'ref = C.new
        c2 C'iso = c1
    SOURCE
    
    expected = <<-MSG
    This type is outside of a constraint: C:
    from (example):5:
        c1 C'ref = C.new
        ^~
    
    - it must be a subtype of C'iso:
      from (example):6:
        c2 C'iso = c1
           ^~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "complains when calling on types without that function" do
    source = Mare::Source.new "(example)", <<-SOURCE
    interface A:
      fun foo:
    
    primitive B:
      fun bar:
    
    class C:
      fun baz:
    
    actor Main:
      new:
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
    interface A:
              ^
    
    - B has no 'baz' function:
      from (example):4:
    primitive B:
              ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "complains when calling with an insufficient receiver capability" do
    source = Mare::Source.new "(example)", <<-SOURCE
    primitive Example:
      fun ref mutate:
    
    actor Main:
      new:
        Example.mutate
    SOURCE
    
    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):6:
        Example.mutate
                ^~~~~~
    
    - the type Example isn't a subtype of the required capability of 'ref':
      from (example):2:
      fun ref mutate:
          ^~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
end
