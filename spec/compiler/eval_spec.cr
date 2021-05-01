describe Mare::Compiler::Eval do
  it "evaluates the semantic tests" do
    source_dir = File.join(__DIR__, "../mare/semantics")

    ctx = Mare.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the prelude tests" do
    source_dir = File.join(__DIR__, "../mare/prelude")

    ctx = Mare.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the collections package's tests" do
    source_dir = File.join(__DIR__, "../../packages/collections/test")

    ctx = Mare.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the time package's tests" do
    source_dir = File.join(__DIR__, "../../packages/time/test")

    ctx = Mare.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the json package's tests" do
    source_dir = File.join(__DIR__, "../../packages/json/test")

    ctx = Mare.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the net package's tests" do
    source_dir = File.join(__DIR__, "../../packages/net/test")

    ctx = Mare.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the bytes package's tests" do
    source_dir = File.join(__DIR__, "../../packages/bytes/test")

    ctx = Mare.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the http/server package's tests" do
    source_dir = File.join(__DIR__, "../../packages/http/server/test")

    ctx = Mare.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end
end
