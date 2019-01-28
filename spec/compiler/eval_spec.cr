describe Mare::Compiler::Eval do
  it "evaluates an example" do
    example_dir = File.join(__DIR__, "../../example")
    
    Mare::Compiler.compile(example_dir, :eval) \
      .program.eval.exitcode.should eq 42
  end
end
