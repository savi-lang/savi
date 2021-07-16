describe Savi::Compiler::Import do
  it "returns the same data structures when compiled again with same sources" do
    source = Savi::Source.new_example <<-SOURCE
    :actor Main
      :new (env)
        env.out.print("Hello, World")
    SOURCE

    ctx1 = Savi.compiler.compile([source], :import)
    ctx2 = Savi.compiler.compile([source], :import)

    ctx1.errors.should be_empty
    ctx2.errors.should be_empty

    ctx1.program.libraries.should eq ctx2.program.libraries
  end
end
