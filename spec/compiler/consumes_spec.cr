describe Mare::Compiler::Consumes do
  it "complains when an already-consumed local is referenced" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = "example"
        --x
        x
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):5:
        x
        ^

    - it was consumed here:
      from (example):4:
        --x
        ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :consumes)
    end
  end

  it "complains when an possibly-consumed local is referenced" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = "example"
        if True (--x)
        x
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):5:
        x
        ^

    - it was consumed here:
      from (example):4:
        if True (--x)
                 ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :consumes)
    end
  end

  it "complains when referencing a possibly-consumed local from a choice" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        @show(1)

      :fun show (u U64)
        if (u <= 3) (
          case (
          | u == 1 | x = "one" // no consume
          | u == 2 | x = "two",   --x
          | u == 2 | x = "three", --x
          |          x = "four",  --x
          )
        |
          x = "four", --x
        )
        x
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):16:
        x
        ^

    - it was consumed here:
      from (example):9:
          | u == 2 | x = "two",   --x
                                  ^~~

    - it was consumed here:
      from (example):10:
          | u == 2 | x = "three", --x
                                  ^~~

    - it was consumed here:
      from (example):11:
          |          x = "four",  --x
                                  ^~~

    - it was consumed here:
      from (example):14:
          x = "four", --x
                      ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :consumes)
    end
  end

  it "allows referencing a local consumed in an earlier choice branch" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        @show(1)

      :fun show (u U64)
        case (
        | u == 1 | --u, x = "one"
        | u == 2 | --u, x = "two"
        | u == 2 | --u, x = "three"
        |          --u, x = "four"
        )
    SOURCE

    Mare::Compiler.compile([source], :consumes)
  end

  it "complains when a choice body uses a local consumed in an earlier cond" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        @show(1)

      :fun show (u U64)
        if (--u == 1) (
          "one"
        |
          u
        )
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):9:
          u
          ^

    - it was consumed here:
      from (example):6:
        if (--u == 1) (
            ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :consumes)
    end
  end

  it "complains when a choice cond uses a local consumed before the choice" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        @show(1)

      :fun show (u U64)
        --u
        if (u == 1) ("one" | "other")
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):7:
        if (u == 1) ("one" | "other")
            ^

    - it was consumed here:
      from (example):6:
        --u
        ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :consumes)
    end
  end

  it "complains when consuming a local in a loop cond" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = "example"
        while --x (True)
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):4:
        while --x (True)
                ^

    - it was consumed here:
      from (example):4:
        while --x (True)
              ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :consumes)
    end
  end

  it "complains when consuming a local in a loop body" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = "example"
        while True (--x)
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):4:
        while True (--x)
                      ^

    - it was consumed here:
      from (example):4:
        while True (--x)
                    ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :consumes)
    end
  end

  it "complains when using a local possibly consumed in a loop else body" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = "example"
        while True (None | --x)
        x
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):5:
        x
        ^

    - it was consumed here:
      from (example):4:
        while True (None | --x)
                           ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :consumes)
    end
  end

  it "allows referencing a local in the body of a loop consumed in the else" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = "example"
        while True (x | --x)
    SOURCE

    Mare::Compiler.compile([source], :consumes)
  end

  it "complains when a loop cond uses a local consumed before the loop" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        @show(1)

      :fun show (u U64)
        --u
        while (u == 1) ("one" | "other")
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):7:
        while (u == 1) ("one" | "other")
               ^

    - it was consumed here:
      from (example):6:
        --u
        ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :consumes)
    end
  end

  pending "allows re-assigning a consumed variable, under certain conditions"
end
