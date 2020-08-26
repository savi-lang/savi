describe Mare::Compiler::Namespace do
  it "returns the same output state when compiled again with same sources" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new (env)
        env.out.print("Hello, World")
    SOURCE

    ctx1 = Mare.compiler.compile([source], :namespace)
    ctx2 = Mare.compiler.compile([source], :namespace)

    ctx1.namespace[source].should eq ctx2.namespace[source]
  end

  it "complains when a type has the same name as another" do
    source = Mare::Source.new_example <<-SOURCE
    :class Redundancy
    :actor Redundancy
    SOURCE

    expected = <<-MSG
    This type conflicts with another declared type in the same library:
    from (example):2:
    :actor Redundancy
           ^~~~~~~~~~

    - the other type with the same name is here:
      from (example):1:
    :class Redundancy
           ^~~~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :namespace)
    end
  end

  it "complains when a function has the same name as another" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun same_name: "This is a contentious function!"
      :prop same_name: "This is a contentious property!"
      :const same_name: "This is a contentious constant!"
    SOURCE

    expected = <<-MSG
    This name conflicts with others declared in the same type:
    from (example):2:
      :fun same_name: "This is a contentious function!"
           ^~~~~~~~~

    - a conflicting declaration is here:
      from (example):3:
      :prop same_name: "This is a contentious property!"
            ^~~~~~~~~

    - a conflicting declaration is here:
      from (example):4:
      :const same_name: "This is a contentious constant!"
             ^~~~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :namespace)
    end
  end

  it "complains when a type has the same name as another" do
    source = Mare::Source.new_example <<-SOURCE
    :class String
    SOURCE

    expected = <<-MSG
    This type's name conflicts with a mandatory built-in type:
    from (example):1:
    :class String
           ^~~~~~

    - the built-in type is defined here:
      from #{Mare::Compiler.prelude_library_path}/string.mare:1:
    :class val String
               ^~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare.compiler.compile([source], :namespace)
    end
  end

  # TODO: Figure out how to test these in our test suite - they need a library.
  pending "complains when a bulk-imported type conflicts with another"
  pending "complains when an explicitly imported type conflicts with another"
  pending "complains when an explicitly imported type conflicts with another"
  pending "complains when a type name ends with an exclamation"

  it "won't have conflicts with a private type in the prelude library" do
    source = Mare::Source.new_example <<-SOURCE
    :ffi LibPony // defined in the prelude, but private, so no conflict here
    SOURCE

    Mare.compiler.compile([source], :namespace)
  end

  # TODO: Figure out how to test these in our test suite - they need a library.
  pending "won't have conflicts with a private type in an imported library"
  pending "complains when trying to explicitly import a private type"
end
