describe Mare::Compiler::Privacy do
  it "complains when calling a private method on a prelude type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        Env._create
    SOURCE

    expected = <<-MSG
    This function call breaks privacy boundaries:
    from (example):3:
        Env._create
            ^~~~~~~

    - this is a private function from another library:
      from #{Mare::Compiler.prelude_library.source_library.path}/env.mare:4:
      :new val _create
               ^~~~~~~
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :privacy)
    end
  end

  pending "won't allow an interface in the local library to circumvent"

  it "won't try (and fail) to check privacy of unreachable choice branches" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Trait
      :fun trait None

    :class Generic (A)
      :prop _value A
      :new (@_value)
      :fun ref value_trait
        if (A <: Trait) (@._value.trait)

    :actor Main
      :new
        Generic(String).new("example").value_trait
    SOURCE

    Mare::Compiler.compile([source], :privacy)
  end
end
