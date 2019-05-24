describe Mare::Compiler::Refer do
  it "fails to resolve a local when it was declared in another branch" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        if True (
          x = "example"
        |
          x
        )
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :refer)
    
    func = ctx.program.find_func!("Main", "new")
    refer = ctx.refers[func]
    x = func
      .body.not_nil!
      .terms.first.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Choice)
      .list.last.last.as(Mare::AST::Group)
      .terms.first
    
    refer[x].class.should eq Mare::Compiler::Refer::Unresolved
  end
  
  it "resolves a local declared in all prior branches" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        if True (
          if True (
            x = "one"
          |
            x = "two"
          )
        |
          x = "three"
        )
        x
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :refer)
    
    func = ctx.program.find_func!("Main", "new")
    refer = ctx.refers[func]
    choice_outer = func
      .body.not_nil!
      .terms.first.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Choice)
    
    choice_inner = choice_outer
      .list[0].last.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Choice)
    
    x1 = choice_inner
      .list[0].last.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Relate)
      .lhs.as(Mare::AST::Identifier)
    
    x2 = choice_inner
      .list[1].last.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Relate)
      .lhs.as(Mare::AST::Identifier)
    
    x3 = choice_outer
      .list[1].last.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Relate)
      .lhs.as(Mare::AST::Identifier)
    
    x = func
      .body.not_nil!
      .terms.last.as(Mare::AST::Identifier)
    
    refer[x].as(Mare::Compiler::Refer::LocalUnion).list.should eq [
      refer[x1].as(Mare::Compiler::Refer::Local),
      refer[x2].as(Mare::Compiler::Refer::Local),
      refer[x3].as(Mare::Compiler::Refer::Local),
    ]
  end
  
  it "complains when referencing a local declared in only some branches" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        if True (
          if True (
            // missing x
          |
            x = "two"
          )
        |
          x = "three"
        )
        x
    SOURCE
    
    expected = <<-MSG
    This variable can't be used here; it was assigned a value in some but not all branches:
    from (example):12:
        x
        ^
    
    - it was assigned here:
      from (example):7:
            x = "two"
            ^
    
    - it was assigned here:
      from (example):10:
          x = "three"
          ^
    
    - but there were other possible branches where it wasn't assigned
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :refer)
    end
  end
  
  it "complains when an already-consumed local is referenced" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        x = "example"
        --x
        x
    SOURCE
    
    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):5:
        x
        ^
    
    - it was consumed here:
      from (example):4:
        --x
        ^~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :refer)
    end
  end
  
  it "complains when an possibly-consumed local is referenced" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        x = "example"
        if True (--x)
        x
    SOURCE
    
    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):5:
        x
        ^
    
    - it was consumed here:
      from (example):4:
        if True (--x)
                 ^~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :refer)
    end
  end
  
  it "complains when a possibly-consumed local from branches is referenced" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      new:
        if True (
          if True (
            x = "one" // no consume
          |
            x = "two", --x
          )
        |
          x = "three", --x
        )
        x
    SOURCE
    
    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):12:
        x
        ^
    
    - it was consumed here:
      from (example):7:
            x = "two", --x
                       ^~~
    
    - it was consumed here:
      from (example):10:
          x = "three", --x
                       ^~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :refer)
    end
  end
end
