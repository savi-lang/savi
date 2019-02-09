describe Mare::Compiler::Completeness do
  it "complains when not all fields get initialized in a constructor" do
    source = Mare::Source.new "(example)", <<-SOURCE
    class Data:
      prop w U64:
      prop x U64:
      prop y U64:
      prop z U64: 4
      new:
        @x = 2
    SOURCE
    
    expected = <<-MSG
    This constructor doesn't initialize all of its fields:
    from (example):6:
      new:
      ^~~
    
    - this field didn't get initialized:
      from (example):2:
      prop w U64:
           ^
    
    - this field didn't get initialized:
      from (example):4:
      prop y U64:
           ^
    MSG
    
    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :completeness)
    end
  end
end
