require "./spec_helper"

describe Mare::Typer do
  it "complains when the function body doesn't match the return type" do
    source = Mare::Source.new "(example)", <<-SOURCE
    primitive Example:
      fun number I32:
        "not a number at all"
    
    actor Main:
      new create:
        Example.number
    SOURCE
    
    ast = Mare::Parser.parse(source)
    ast.should be_truthy
    next unless ast
    
    context = Mare::Context.new
    context.compile(ast)
    context.run(Mare::Sugar)
    
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
    
    expect_raises Mare::Typer::Error, expected do
      context.run(Mare::Typer)
    end
  end
end
