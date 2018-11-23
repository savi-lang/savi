require "./spec_helper"

describe Mare::Compiler::Default do
  it "compiles an example" do
    source = fixture "compile.mare"
    
    ast = Mare::Parser.parse(source)
    ast.should be_truthy
    next unless ast
    
    context = Mare::Context.new
    context.compile(ast)
    context.finish
    context.run(Mare::CodeGen.new).should eq 42
  end
end
