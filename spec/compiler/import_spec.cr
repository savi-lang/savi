describe Mare::Compiler::Import do
  it "returns the same AST when compiled again with the same source" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Example
      :const greeting String: "Hello, World!"
    SOURCE

    ctx1 = Mare::Compiler.compile([source], :import)
    ctx2 = Mare::Compiler.compile([source], :import)

    ctx1.program.libraries.should eq ctx2.program.libraries
  end
end
