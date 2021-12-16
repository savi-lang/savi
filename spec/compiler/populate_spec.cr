describe Savi::Compiler::Populate do
  it "complains when a source type couldn't be resolved" do
    source = Savi::Source.new_example <<-SOURCE
    :actor Main
      :is Bogus
    SOURCE

    expected = <<-MSG
    This type couldn't be resolved:
    from (example):2:
      :is Bogus
          ^~~~~
    MSG

    Savi.compiler.test_compile([source], :populate)
      .errors.map(&.message).join("\n").should eq expected
  end
end
