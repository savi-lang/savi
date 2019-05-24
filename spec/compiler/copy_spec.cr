describe Mare::Compiler::Infer do
  it "complains when a source type couldn't be resolved" do
    source = Mare::Source.new "(example)", <<-SOURCE
    actor Main:
      is Bogus:
    SOURCE
    
    expected = <<-MSG
    This type couldn't be resolved:
    from (example):2:
      is Bogus:
         ^~~~~
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :copy)
    end
  end
end
