describe Savi::Compiler::ServeDefinition do
  it "can find class definition" do
    source = Savi::Source.new_example <<-SOURCE
    :class A

    :actor Main
      :new
        example = A.new
    SOURCE

    ctx = Savi.compiler.compile([source], :serve_definition)
    ctx.errors.should be_empty

    pos = ctx.serve_definition[Savi::Source::Pos.point(source, 4, 14)].not_nil!
    pos.row.should eq 0
    pos.col.should eq 7
    pos.size.should eq "A".bytesize
  end

  it "can find local variable declaration" do
    source = Savi::Source.new_example <<-SOURCE
    :actor Main
      :new
        example = "Hello, World!"
        example1 = example

        example2 = example1 * 1
    SOURCE

    ctx = Savi.compiler.compile([source], :serve_definition)
    ctx.errors.should be_empty

    pos = ctx.serve_definition[Savi::Source::Pos.point(source, 3, 21)].not_nil!
    pos.row.should eq 2
    pos.col.should eq 4
    pos.size.should eq "example".bytesize

    pos = ctx.serve_definition[Savi::Source::Pos.point(source, 5, 15)].not_nil!
    pos.row.should eq 3
    pos.col.should eq 4
    pos.size.should eq "example1".bytesize

    pos = ctx.serve_definition[Savi::Source::Pos.point(source, 5, 8)].not_nil!
    pos.row.should eq 5
    pos.col.should eq 4
    pos.size.should eq "example2".bytesize
  end

  it "can find method declaration" do
    source = Savi::Source.new_example <<-SOURCE
    :class A
      :new

      :new new_iso

      :fun test

    :actor Main
      :new
        example = A.new
        example1 = A.new_iso
        example2 = example1.test
    SOURCE

    ctx = Savi.compiler.compile([source], :serve_definition)
    ctx.errors.should be_empty

    pos = ctx.serve_definition[Savi::Source::Pos.point(source, 9, 18)].not_nil!
    pos.row.should eq 1
    pos.col.should eq 3
    pos.size.should eq "new".bytesize

    pos = ctx.serve_definition[Savi::Source::Pos.point(source, 10, 18)].not_nil!
    pos.row.should eq 3
    pos.col.should eq 7
    pos.size.should eq "new_iso".bytesize

    pos = ctx.serve_definition[Savi::Source::Pos.point(source, 11, 25)].not_nil!
    pos.row.should eq 5
    pos.col.should eq 7
    pos.size.should eq "test".bytesize
  end
end
