require "./spec_helper"

describe Mare::Typer do
  it "complains when the function body doesn't match the return type" do
    source = Mare::Source.new "(example)", <<-SOURCE
    primitive I32:     // TODO: implicit prelude with builtin types
    primitive CString: // TODO: implicit prelude with builtin types
    
    primitive Example:
      fun number I32:
        "not a number at all"
    
    actor Main:
      new:
        Example.number
    SOURCE
    
    ast = Mare::Parser.parse(source)
    ast.should be_truthy
    next unless ast
    
    context = Mare::Context.new
    context.compile(ast)
    context.run(Mare::Sugar)
    context.run(Mare::Refer)
    
    expected = <<-MSG
    This value's type is unresolvable due to conflicting constraints:
    - it must be a subtype of (CString):
      from (example):6:
        "not a number at all"
         ^~~~~~~~~~~~~~~~~~~
    
    - it must be a subtype of (I32):
      from (example):5:
      fun number I32:
                 ^~~
    MSG
    
    expect_raises Mare::Typer::Error, expected do
      context.run(Mare::Typer)
    end
  end
  
  it "complains when the assignment type doesn't match the right-hand-side" do
    source = Mare::Source.new "(example)", <<-SOURCE
    primitive I32:     // TODO: implicit prelude with builtin types
    primitive CString: // TODO: implicit prelude with builtin types
    
    primitive Example:
      fun number I32:
        42
    
    actor Main:
      new:
        name CString = Example.number
    SOURCE
    
    ast = Mare::Parser.parse(source)
    ast.should be_truthy
    next unless ast
    
    context = Mare::Context.new
    context.compile(ast)
    context.run(Mare::Sugar)
    context.run(Mare::Refer)
    
    expected = <<-MSG
    This value's type is unresolvable due to conflicting constraints:
    - it must be a subtype of (CString):
      from (example):10:
        name CString = Example.number
             ^~~~~~~
    
    - it must be a subtype of (I32):
      from (example):5:
      fun number I32:
                 ^~~
    MSG
    
    expect_raises Mare::Typer::Error, expected do
      context.run(Mare::Typer)
    end
  end
end
