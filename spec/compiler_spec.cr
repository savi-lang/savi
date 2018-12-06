require "./spec_helper"

describe Mare do
  it "compiles an example" do
    source = fixture "compile.mare"
    
    ast = Mare::Parser.parse(source)
    ast.should be_truthy
    next unless ast
    
    context = Mare::Context.new
    context.compile(ast)
    context.run(Mare::Sugar)
    context.run(Mare::Flagger)
    context.run(Mare::Refer)
    context.run(Mare::Typer)
    context.run(Mare::CodeGen.new).return_value.should eq 42
  end
end
