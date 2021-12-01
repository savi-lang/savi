describe Savi::Compiler::Eval do
  it "complains if there is no Main actor defined in the root library" do
    content = <<-SOURCE
    :module Example
    SOURCE

    source = Savi::Source.new(
      "/path/to/fake/example/library",
      "example.savi",
      content,
      Savi::Source::Library.new("/path/to/fake/example/library"),
    )

    expected = <<-MSG
    This is the root directory being compiled, but it has no Main actor:
    from /path/to/fake/example/library/:1:
    /path/to/fake/example/library
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MSG

    Savi.compiler.compile([source], :eval)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "evaluates the semantic tests" do
    source_dir = File.join(__DIR__, "../savi/semantics")

    ctx = Savi.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the savi tests" do
    source_dir = File.join(__DIR__, "../../packages/savi/test")

    ctx = Savi.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the collections package's tests" do
    source_dir = File.join(__DIR__, "../../packages/collections/test")

    ctx = Savi.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the Time package's tests" do
    source_dir = File.join(__DIR__, "../../packages/Time/test")

    ctx = Savi.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the JSON package's tests" do
    source_dir = File.join(__DIR__, "../../packages/JSON/test")

    ctx = Savi.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the net package's tests" do
    source_dir = File.join(__DIR__, "../../packages/net/test")

    ctx = Savi.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the bytes package's tests" do
    source_dir = File.join(__DIR__, "../../packages/bytes/test")

    ctx = Savi.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the http/server package's tests" do
    source_dir = File.join(__DIR__, "../../packages/http/server/test")

    ctx = Savi.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end

  it "evaluates the Regex package's tests" do
    source_dir = File.join(__DIR__, "../../packages/Regex/test")

    ctx = Savi.compiler.compile(source_dir, :eval)
    ctx.errors.should be_empty

    no_test_failures = ctx.eval.exitcode == 0
    no_test_failures.should eq true
  end
end
