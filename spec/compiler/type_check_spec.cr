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

  it "complains when the assignment type doesn't match the right-hand-side" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        name String = 42
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):3:
        name String = 42
                      ^~

    - it is required here to be a subtype of String:
      from (example):3:
        name String = 42
             ^~~~~~

    - but the type of the literal value was Numeric:
      from (example):3:
        name String = 42
                      ^~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when the prop type doesn't match the initializer value" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :prop name String: 42
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):2:
      :prop name String: 42
                         ^~

    - it is required here to be a subtype of String:
      from (example):2:
      :prop name String: 42
                 ^~~~~~

    - but the type of the literal value was Numeric:
      from (example):2:
      :prop name String: 42
                         ^~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "treats an empty sequence as producing None" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        name String = ()
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):3:
        name String = ()
                      ^~

    - it is required here to be a subtype of String:
      from (example):3:
        name String = ()
             ^~~~~~

    - but the type of the expression was None:
      from (example):3:
        name String = ()
                      ^~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  it "complains when a choice condition type isn't boolean" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        if "not a boolean" 42
    SOURCE

    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):3:
        if "not a boolean" 42
        ^~

    - it is required here to be a subtype of Bool:
      from (example):3:
        if "not a boolean" 42
        ^~

    - but the type of the expression was String:
      from (example):3:
        if "not a boolean" 42
            ^~~~~~~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  # ...

  it "complains when unable to infer mutually recursive return types" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Tweedle
      :fun dee (n I32): Tweedle.dum(n)
      :fun dum (n I32): Tweedle.dee(n)

    :actor Main
      :new
        Tweedle.dum(42)
    SOURCE

    expected = <<-MSG
    This return value needs an explicit type; it could not be inferred:
    from (example):3:
      :fun dum (n I32): Tweedle.dee(n)
                                ^~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :type_check)
    end
  end

  # ...
end
