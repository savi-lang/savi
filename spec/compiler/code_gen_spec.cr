require "./spec_helper"

describe Mare::Compiler::CodeGen do
  it "compiles an example" do
    source = fixture "compile.mare"
    
    Mare::Compiler.compile(source).program.code_gen.return_value.should eq 42
  end
end
