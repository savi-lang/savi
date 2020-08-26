describe Mare::Compiler::Eval do
  it "evaluates the semantic tests" do
    source_dir = File.join(__DIR__, "../mare/semantics")

    no_test_failures =
      Mare.compiler.compile(source_dir, :eval).eval.exitcode == 0

    no_test_failures.should eq true
  end

  it "evaluates the prelude tests" do
    source_dir = File.join(__DIR__, "../mare/prelude")

    no_test_failures =
      Mare.compiler.compile(source_dir, :eval).eval.exitcode == 0

    no_test_failures.should eq true
  end

  it "evaluates the collections package's tests" do
    source_dir = File.join(__DIR__, "../../packages/collections/test")

    no_test_failures =
      Mare.compiler.compile(source_dir, :eval).eval.exitcode == 0

    no_test_failures.should eq true
  end

  it "evaluates the time package's tests" do
    source_dir = File.join(__DIR__, "../../packages/time/test")

    no_test_failures =
      Mare.compiler.compile(source_dir, :eval).eval.exitcode == 0

    no_test_failures.should eq true
  end

  it "evaluates the json package's tests" do
    source_dir = File.join(__DIR__, "../../packages/json/test")

    no_test_failures =
      Mare.compiler.compile(source_dir, :eval).eval.exitcode == 0

    no_test_failures.should eq true
  end
end
