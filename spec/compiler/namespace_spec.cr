describe Savi::Compiler::Namespace do
  it "returns the same output state when compiled again with same sources" do
    source = Savi::Source.new_example <<-SOURCE
    :actor Main
      :new (env)
        env.out.print("Hello, World")
    SOURCE

    ctx1 = Savi.compiler.test_compile([source], :namespace)
    ctx2 = Savi.compiler.test_compile([source], :namespace)

    ctx1.namespace[source].should eq ctx2.namespace[source]
  end

  # TODO: Figure out how to test these in our test suite - they need a package.
  pending "complains when a bulk-imported type conflicts with another"
  pending "won't have conflicts with a private type in an imported package"
  pending "complains when trying to explicitly import a private type"
end
