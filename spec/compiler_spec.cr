require "./spec_helper"

describe Mare::Compiler::Default do
  it "compiles an example" do
    source = fixture "compile.mare"
    
    ast = Mare::Parser.parse(source)
    ast.should be_truthy
    next unless ast
    
    ast.accept(Mare::Sugar.new)
    
    context = Mare::Context.new
    context.compile(ast)
    context.run(Mare::CodeGen.new).return_value.should eq 42
  end
end
