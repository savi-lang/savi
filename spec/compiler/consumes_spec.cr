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

    Mare.compiler.compile([source], :consumes)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :consumes)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when an already-consumed @ is referenced" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun iso call
        result = --@
        @.call
        result

    :actor Main
      :new
        Example.call
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):4:
        @.call
        ^

    - it was consumed here:
      from (example):3:
        result = --@
                 ^~~
    MSG

    Mare.compiler.compile([source], :consumes)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :consumes)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :consumes)
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

    Mare.compiler.compile([source], :consumes)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :consumes)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :consumes)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :consumes)
      .errors.map(&.message).join("\n").should eq expected
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

    Mare.compiler.compile([source], :consumes)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "allows referencing a local in the body of a loop consumed in the else" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = "example"
        while True (x | --x)
    SOURCE

    Mare.compiler.compile([source], :consumes)
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

    Mare.compiler.compile([source], :consumes)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "unconsumes a variable if assigned from an expression that consumes it" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun non @indirect (s String'iso) String'iso: s
      :fun non @indirect_partial! (s String'iso) String'iso: s
      :new
        x = String.new_iso
        x = @indirect(--x) // okay; unconsumed
        x
        if True (x = @indirect(--x)) // okay; unconsumed
        x
        i U8 = 0, while (i < 5) (i += 1, x = @indirect(--x)) // okay; unconsumed
        x
        try (x = @indirect(--x), error!) // okay; unconsumed
        x
        try (x = @indirect_partial!(--x)) // NOT OKAY; reassignment is partial
        x
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it might already be consumed:
    from (example):15:
        x
        ^

    - it was consumed here:
      from (example):14:
        try (x = @indirect_partial!(--x)) // NOT OKAY; reassignment is partial
                                    ^~~
    MSG

    Mare.compiler.compile([source], :consumes)
      .errors.map(&.message).join("\n").should eq expected
  end
end
