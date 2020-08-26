describe Mare::Compiler::Import do
  it "returns the same data structures when compiled again with same sources" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new (env)
        env.out.print("Hello, World")
    SOURCE

    ctx1 = Mare.compiler.compile([source], :import)
    ctx2 = Mare.compiler.compile([source], :import)

    ctx1.program.libraries.should eq ctx2.program.libraries
  end
end
