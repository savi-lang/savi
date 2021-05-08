describe Mare::Compiler::Eval do
  it "complains if there is no Main actor defined in the root library" do
    content = <<-SOURCE
    :primitive Example
    SOURCE

    source = Mare::Source.new(
      "example.mare",
      content,
      Mare::Source::Library.new("/path/to/fake/example/library"),
    )

    expected = <<-MSG
    This is the root directory being compiled, but it has no Main actor:
    from /path/to/fake/example/library/:1:
    /path/to/fake/example/library
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :eval)
      .errors.map(&.message).join("\n").should eq expected
  end

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
