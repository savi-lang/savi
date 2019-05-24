describe Mare::Compiler::Eval do
  it "evaluates an example" do
    example_dir = File.join(__DIR__, "../../example")
    
    Mare::Compiler.compile(example_dir, :eval) \
      .eval.exitcode.should eq 42
  end
  
  it "evaluates the prelude tests" do
    source = fixture "prelude_tests.mare"
    
    no_test_failures =
      Mare::Compiler.compile([source], :eval).eval.exitcode == 0
    
    no_test_failures.should eq true
  end
end
