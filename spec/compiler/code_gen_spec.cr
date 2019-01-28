describe Mare::Compiler::CodeGen do
  it "compiles an example" do
    example_dir = File.join(__DIR__, "../../example")
    
    Mare::Compiler.compile(example_dir).program.code_gen.jit!.should eq 42
  end
end
