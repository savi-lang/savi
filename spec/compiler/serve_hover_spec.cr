describe Mare::Compiler::ServeHover do
  it "describes a local variable and its method" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        example = "Hello, World!"
        example.hash
    SOURCE
    
    ctx = Mare::Compiler.compile([source], :serve_hover)
    
    messages, pos = ctx.serve_hover[Mare::Source::Pos.point(source, 2, 5)]
    pos.row.should eq 2
    pos.col.should eq 4
    pos.size.should eq "example".bytesize
    messages.should eq [
      "This is a local variable.",
      "It has an inferred type of String.",
    ]
    
    messages, pos = ctx.serve_hover[Mare::Source::Pos.point(source, 3, 5)]
    pos.row.should eq 3
    pos.col.should eq 4
    pos.size.should eq "example".bytesize
    messages.should eq [
      "This is a local variable.",
      "It has an inferred type of String.",
    ]
    
    messages, pos = ctx.serve_hover[Mare::Source::Pos.point(source, 3, 13)]
    pos.row.should eq 3
    pos.col.should eq 4
    pos.size.should eq "example.hash".bytesize
    messages.should eq [
      "This is a function call on an inferred receiver type of String.",
      "It has an inferred return type of USize."
    ]
  end
end
