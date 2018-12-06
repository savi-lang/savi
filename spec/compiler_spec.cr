require "./spec_helper"

describe Mare do
  it "compiles an example" do
    source = fixture "compile.mare"
    
    ast = Mare::Parser.parse(source)
    ast.should be_truthy
    next unless ast
    
    context = Mare::Compiler::Context.new
    context.compile(ast)
    context.run(Mare::Compiler::Sugar)
    context.run(Mare::Compiler::Flagger)
    context.run(Mare::Compiler::Refer)
    context.run(Mare::Compiler::Typer)
    context.run(Mare::Compiler::CodeGen.new).return_value.should eq 42
  end
end
