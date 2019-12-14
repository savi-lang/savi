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

  it "describes a self-call" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun example U64: 0
      :new
        @example
    SOURCE

    ctx = Mare::Compiler.compile([source], :serve_hover)

    messages, pos = ctx.serve_hover[Mare::Source::Pos.point(source, 3, 6)]
    pos.row.should eq 3
    pos.col.should eq 4
    pos.size.should eq "@example".bytesize
    messages.should eq [
      "This is a function call on an inferred receiver type of Main'ref.",
      "It has an inferred return type of U64.",
    ]
  end

  it "describes an expression nested inside several layers of flow control" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun example U64: 0
      :new
        x U64 = 0
        while (x < 100) (
          if (x == 36) (
            example = x
            example
          )
          x += 1
        )
    SOURCE

    ctx = Mare::Compiler.compile([source], :serve_hover)

    messages, pos = ctx.serve_hover[Mare::Source::Pos.point(source, 7, 9)]
    pos.row.should eq 7
    pos.col.should eq 8
    pos.size.should eq "example".bytesize
    messages.should eq [
      "This is a local variable.",
      "It has an inferred type of U64.",
    ]
  end
end
