describe Mare::Compiler::TypeCheck do
  it "complains when the type identifier couldn't be resolved" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x BogusType = 42
    SOURCE

    expected = <<-MSG
    This type couldn't be resolved:
    from (example):3:
        x BogusType = 42
          ^~~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when the return type identifier couldn't be resolved" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun x BogusType: 42
      :new
        @x
    SOURCE

    expected = <<-MSG
    This type couldn't be resolved:
    from (example):2:
      :fun x BogusType: 42
             ^~~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when the local identifier couldn't be resolved" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        x = y
    SOURCE

    expected = <<-MSG
    This identifer couldn't be resolved:
    from (example):3:
        x = y
            ^
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when a local identifier wasn't declared, even when unused" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        bogus
    SOURCE

    expected = <<-MSG
    This identifer couldn't be resolved:
    from (example):3:
        bogus
        ^~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when the function body doesn't match the return type" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Example
      :fun number I32
        "not a number at all"

    :actor Main
      :new
        Example.number
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):3:
        "not a number at all"
         ^~~~~~~~~~~~~~~~~~~

    - it is required here to be a subtype of I32:
      from (example):2:
      :fun number I32
                  ^~~

    - but the type of the expression was String:
      from (example):3:
        "not a number at all"
         ^~~~~~~~~~~~~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end
end
