require "../../spec_helper"

describe Mare::Compiler::Interpreter::Default do
  it "complains when the function doesn't have a space before the params" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :fun example(x U64)
        x
    SOURCE

    expected = <<-MSG
    Expected a term of type: ident or string:
    from (example):2:
      :fun example(x U64)
           ^~~~~~~~~~~~~~

    - you probably need to add a space to separate it from this next term:
      from (example):2:
      :fun example(x U64)
                  ^~~~~~~
    MSG

    Mare.compiler.compile([source], :import)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when a capability is specified for a behaviour" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Example
      :be ref example
        None
    SOURCE

    expected = <<-MSG
    A behaviour can't have an explicit receiver capability:
    from (example):2:
      :be ref example
          ^~~
    MSG

    Mare.compiler.compile([source], :import)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "correctly handles an explicit union return type" do
    source = Mare::Source.new_example <<-SOURCE
    :trait Greeter
      :fun greeting (String | None)
    SOURCE

    ctx = Mare.compiler.compile([source], :import)
    ctx.errors.should be_empty

    greeter = ctx.program.types.first
    greeting = greeter.functions.first
    greeting.params.should eq nil
    greeting.ret.not_nil!.to_a.pretty_inspect(74).should eq <<-AST
    [:group,
     "|",
     [:group, "(", [:ident, "String"]],
     [:group, "(", [:ident, "None"]]]
    AST
  end
end
