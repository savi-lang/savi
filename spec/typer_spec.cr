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
    This can't be a subtype of (I32) because of other constraints:
    - this must be a subtype of (CString):
      from (example):3:
        "not a number at all"
         ^~~~~~~~~~~~~~~~~~~
    MSG
    
    expect_raises Mare::Typer::Error, expected do
      context.run(Mare::Typer)
    end
  end
end
