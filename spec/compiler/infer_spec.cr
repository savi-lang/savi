describe Mare::Compiler::Infer do
  it "complains when the type identifier couldn't be resolved" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        x BogusType = 42
    SOURCE
    
    expected = <<-MSG
    This identifer couldn't be resolved:
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
    
    - it must be a subtype of CString:
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
        name CString = 42
    SOURCE
    
    expected = <<-MSG
    This value's type is unresolvable due to conflicting constraints:
    from (example):3:
        name CString = 42
                       ^~

    - it must be a subtype of Numeric:
      from (example):3:
        name CString = 42
                       ^~
    
    - it must be a subtype of CString:
      from (example):3:
        name CString = 42
             ^~~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "complains when the prop type doesn't match the initializer value" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      prop name CString: 42
    SOURCE
    
    expected = <<-MSG
    This value's type is unresolvable due to conflicting constraints:
    from (example):2:
      prop name CString: 42
                         ^~
    
    - it must be a subtype of Numeric:
      from (example):2:
      prop name CString: 42
                         ^~
    
    - it must be a subtype of CString:
      from (example):2:
      prop name CString: 42
                ^~~~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :infer)
    end
  end
  
  it "treats an empty sequence as producing None" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        name CString = ()
    SOURCE
    
    expected = <<-MSG
    This value's type is unresolvable due to conflicting constraints:
    from (example):3:
        name CString = ()
                       ^~
    
    - it must be a subtype of None:
      from (example):3:
        name CString = ()
                       ^~
    
    - it must be a subtype of CString:
      from (example):3:
        name CString = ()
             ^~~~~~~
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
    
    - it must be a subtype of CString:
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
    
    func.infer.resolve(assign.lhs).defns.map(&.ident).map(&.value).should eq \
      ["CString"]
    
    func.infer.resolve(assign.rhs).defns.map(&.ident).map(&.value).should eq \
      ["CString"]
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
    
    func.infer.resolve(prop).defns.map(&.ident).map(&.value).should eq \
      ["CString"]
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
    
    func.infer.resolve(assign.lhs).defns.map(&.ident).map(&.value).should eq \
      ["U64", "None"]
    
    func.infer.resolve(assign.rhs).defns.map(&.ident).map(&.value).should eq \
      ["U64"]
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
    
    func.infer.resolve(prop).defns.map(&.ident).map(&.value).should eq ["U64"]
  end
  
  it "infers an integer literal through an if statement" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        x (U64 | CString | None) = if True 42
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :infer)
    
    func = ctx.program.find_func!("Main", "new")
    body = func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    literal = assign.rhs
      .as(Mare::AST::Group).terms.last
      .as(Mare::AST::Choice).list[0][1]
      .as(Mare::AST::LiteralInteger)
    
    func.infer.resolve(assign.lhs).defns.map(&.ident).map(&.value).should eq \
      ["U64", "CString", "None"]
    
    func.infer.resolve(assign.rhs).defns.map(&.ident).map(&.value).should eq \
      ["U64", "None"]
    
    func.infer.resolve(literal).defns.map(&.ident).map(&.value).should eq \
      ["U64"]
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
      
      func.infer.resolve(call).defns.map(&.ident).map(&.value).should eq \
        ["I32"]
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
      
      func.infer.resolve(expr).defns.map(&.ident).map(&.value).should eq ["I32"]
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
    interface Interface:
      fun example Interface:
    
    primitive Concrete:
      fun example Concrete: Concrete
    
    actor Main:
      new:
        i Interface = Concrete
    SOURCE
    
    Mare::Compiler.compile([source], :infer)
  end
  
  it "complains when an interface has a covariant argument type" do
    source = Mare::Source.new "(example)", <<-SOURCE
    interface Interface:
      fun example (arg Interface) None:
    
    primitive Concrete:
      fun example (arg Concrete) None: None
    
    actor Main:
      new:
        i Interface = Concrete
    SOURCE
    
    expected = <<-MSG
    This type is outside of a constraint:
    from (example):9:
        i Interface = Concrete
                      ^~~~~~~~
    
    - it must be a subtype of Interface:
      from (example):9:
        i Interface = Concrete
          ^~~~~~~~~
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
    This type is outside of a constraint:
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
    
    func.infer.resolve(assign.lhs).defns.map(&.ident).map(&.value).should eq \
      ["X"]
    
    func.infer.resolve(assign.rhs).defns.map(&.ident).map(&.value).should eq \
      ["X"]
  end
end
