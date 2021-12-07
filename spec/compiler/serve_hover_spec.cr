describe Savi::Compiler::ServeHover do
  it "describes a local variable and its method" do
    source = Savi::Source.new_example <<-SOURCE
    :actor Main
      :new
        example = "Hello, World!"
        example.hash
    SOURCE

    ctx = Savi.compiler.test_compile([source], :serve_hover)
    ctx.errors.should be_empty

    messages, pos = ctx.serve_hover[Savi::Source::Pos.point(source, 2, 5)]
    pos.row.should eq 2
    pos.col.should eq 4
    pos.size.should eq "example".bytesize
    messages.should eq [
      "This is a local variable.",
      "It has an inferred type of: String",
    ]

    messages, pos = ctx.serve_hover[Savi::Source::Pos.point(source, 3, 5)]
    pos.row.should eq 3
    pos.col.should eq 4
    pos.size.should eq "example".bytesize
    messages.should eq [
      "This is a local variable.",
      "It has an inferred type of: String",
    ]

    messages, pos = ctx.serve_hover[Savi::Source::Pos.point(source, 3, 13)]
    pos.row.should eq 3
    pos.col.should eq 12
    pos.size.should eq "hash".bytesize
    messages.should eq [
      "This is a function call on type: String",
      "It has an inferred return type of: USize"
    ]
  end

  it "describes a self-call" do
    source = Savi::Source.new_example <<-SOURCE
    :actor Main
      :fun example U64: 0
      :new
        @example
    SOURCE

    ctx = Savi.compiler.test_compile([source], :serve_hover)
    ctx.errors.should be_empty

    messages, pos = ctx.serve_hover[Savi::Source::Pos.point(source, 3, 6)]
    pos.row.should eq 3
    pos.col.should eq 5
    pos.size.should eq "example".bytesize
    messages.should eq [
      "This is a function call on type: Main'ref",
      "It has an inferred return type of: U64",
    ]
  end

  it "describes an expression nested inside several layers of flow control" do
    source = Savi::Source.new_example <<-SOURCE
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

    ctx = Savi.compiler.test_compile([source], :serve_hover)
    ctx.errors.should be_empty

    messages, pos = ctx.serve_hover[Savi::Source::Pos.point(source, 7, 9)]
    pos.row.should eq 7
    pos.col.should eq 8
    pos.size.should eq "example".bytesize
    messages.should eq [
      "This is a local variable.",
      "It has an inferred type of: U64",
    ]
  end

  it "describes type spans, even if not in a pretty way yet" do
    source = Savi::Source.new_example <<-SOURCE
    :actor Main
      :let buffer String'ref: String.new
      :fun buffer_size: @buffer.size
      :new
        @buffer_size
    SOURCE

    ctx = Savi.compiler.test_compile([source], :serve_hover)
    ctx.errors.should be_empty

    messages, pos = ctx.serve_hover[Savi::Source::Pos.point(source, 2, 23)]
    pos.row.should eq 2
    pos.col.should eq 21
    pos.size.should eq "buffer".bytesize
    messages.should eq [
      "This is a function call on type span:\n" +
      "Span({\n" +
      "  BitArray[100] => Main'ref\n" +
      "  BitArray[010] => Main'val\n" +
      "  BitArray[001] => Main'box })",
      "It has an inferred return type span of:\n" +
      "Span({\n" +
      "  BitArray[100] => String'ref\n" +
      "  BitArray[010] => String\n" +
      "  BitArray[001] => String'box })",
    ]
  end
end
