describe Savi::Compiler::Populate do
  it "complains when a function conflicts with a nested type" do
    source = Savi::Source.new_example <<-SOURCE
    :module Example.Nested
    :module Example
      :fun Nested: "example nested"
    SOURCE

    expected = <<-MSG
    This conflicts with the name of a nested type:
    from (example):3:
      :fun Nested: \"example nested\"
           ^~~~~~

    - the nested type is defined here:
      from (example):1:
    :module Example.Nested
            ^~~~~~~~~~~~~~
    MSG

    Savi.compiler.compile([source], :populate)
      .errors.map(&.message).join("\n").should eq expected
  end

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

    Savi.compiler.compile([source], :populate)
      .errors.map(&.message).join("\n").should eq expected
  end
end
