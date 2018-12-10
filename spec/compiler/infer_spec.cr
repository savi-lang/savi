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
    
    expect_raises Mare::Compiler::Infer::Error, expected do
      Mare::Compiler.compile(source, limit: Mare::Compiler::Infer)
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
    
    expect_raises Mare::Compiler::Infer::Error, expected do
      Mare::Compiler.compile(source, limit: Mare::Compiler::Infer)
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
    - it must be a subtype of (CString):
      from (example):3:
        "not a number at all"
         ^~~~~~~~~~~~~~~~~~~
    
    - it must be a subtype of (I32):
      from (example):2:
      fun number I32:
                 ^~~
    MSG
    
    expect_raises Mare::Compiler::Infer::Error, expected do
      Mare::Compiler.compile(source, limit: Mare::Compiler::Infer)
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
    - it must be a subtype of (U8 | U32 | U64 | I8 | I32 | I64 | F32 | F64):
      from (example):3:
        name CString = 42
                       ^~
    
    - it must be a subtype of (CString):
      from (example):3:
        name CString = 42
             ^~~~~~~
    MSG
    
    expect_raises Mare::Compiler::Infer::Error, expected do
      Mare::Compiler.compile(source, limit: Mare::Compiler::Infer)
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
    - it must be a subtype of (CString):
      from (example):3:
        if "not a boolean" 42
            ^~~~~~~~~~~~~
    
    - it must be a subtype of (True | False):
      from (example):3:
        if "not a boolean" 42
        ^~
    MSG
    
    expect_raises Mare::Compiler::Infer::Error, expected do
      Mare::Compiler.compile(source, limit: Mare::Compiler::Infer)
    end
  end
  
  it "infers an integer literal based on an assignment" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        x (U64 | None) = 42
    SOURCE
    
    ctx = Mare::Compiler.compile(source, limit: Mare::Compiler::Infer)
    
    func = ctx.program.find_func!("Main", "new")
    body = func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    
    local_types = func.infer[assign.lhs].resolve!(func.infer)
    local_types.map(&.ident).map(&.value).should eq ["U64", "None"]
    
    literal_types = func.infer[assign.rhs].resolve!(func.infer)
    literal_types.map(&.ident).map(&.value).should eq ["U64"]
  end
  
  it "infers an integer literal through an if statement" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        x (U64 | CString | None) = if True 42
    SOURCE
    
    ctx = Mare::Compiler.compile(source, limit: Mare::Compiler::Infer)
    
    func = ctx.program.find_func!("Main", "new")
    body = func.body.not_nil!
    assign = body.terms.first.as(Mare::AST::Relate)
    literal = assign.rhs
      .as(Mare::AST::Group).terms.last
      .as(Mare::AST::Choice).list[0][1]
      .as(Mare::AST::LiteralInteger)
    
    local_types = func.infer[assign.lhs].resolve!(func.infer)
    local_types.map(&.ident).map(&.value).should eq ["U64", "CString", "None"]
    
    choice_types = func.infer[assign.rhs].resolve!(func.infer)
    choice_types.map(&.ident).map(&.value).should eq ["U64", "None"]
    
    literal_types = func.infer[literal].resolve!(func.infer)
    literal_types.map(&.ident).map(&.value).should eq ["U64"]
  end
end
