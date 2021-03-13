describe Mare::Compiler::Infer do
  it "complains when calling on a function with too many arguments" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
      :new
        @example(1, 2, 3)
        @example(1, 2, 3, 4)
        @example(1, 2, 3, 4, 5)
        @example(1, 2, 3, 4, 5, 6)
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):7:
        @example(1, 2, 3, 4, 5, 6)
         ^~~~~~~

    - the call site has too many arguments:
      from (example):7:
        @example(1, 2, 3, 4, 5, 6)
         ^~~~~~~

    - the function allows at most 5 arguments:
      from (example):2:
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when calling on a function with too few arguments" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
      :new
        @example(1, 2, 3, 4, 5)
        @example(1, 2, 3, 4)
        @example(1, 2, 3)
        @example(1, 2)
    SOURCE

    expected = <<-MSG
    This function call doesn't meet subtyping requirements:
    from (example):7:
        @example(1, 2)
         ^~~~~~~

    - the call site has too few arguments:
      from (example):7:
        @example(1, 2)
         ^~~~~~~

    - the function requires at least 3 arguments:
      from (example):2:
      :fun example (a U8, b U8, c U8, d U8 = 4, e U8 = 5)
                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "infers prop setters to return the alias of the assigned value" do
    source = Mare::Source.new_example <<-SOURCE
    :class Inner
      :new trn:

    :class Outer
      :prop inner Inner'trn: Inner.new

    :actor Main
      :new
        outer = Outer.new
        inner_box Inner'box = outer.inner = Inner.new // okay
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
    SOURCE

    # TODO: Fix position reporting that isn't quite right here:
    expected = <<-MSG
    The type of this expression doesn't meet the constraints imposed on it:
    from (example):11:
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
        ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    - it is required here to be a subtype of Inner'trn:
      from (example):11:
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
                  ^~~~~~~~~

    - but the type of the return value was Inner'box:
      from (example):11:
        inner_trn Inner'trn = outer.inner = Inner.new // not okay
                                    ^~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains if some params of an elevated constructor are not sendable" do
    source = Mare::Source.new_example <<-SOURCE
    :class Example
      :new val (a String'ref, b String'val, c String'box)
        None

    :actor Main
      :new
        Example.new(String.new, "", "")
    SOURCE

    expected = <<-MSG
    A constructor with elevated capability must only have sendable parameters:
    from (example):2:
      :new val (a String'ref, b String'val, c String'box)
           ^~~

    - this parameter type (String'ref) is not sendable:
      from (example):2:
      :new val (a String'ref, b String'val, c String'box)
                ^~~~~~~~~~~~

    - this parameter type (String'box) is not sendable:
      from (example):2:
      :new val (a String'ref, b String'val, c String'box)
                                            ^~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains if some params of an asynchronous function are not sendable" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Example
      :be call (a String'ref, b String'val, c String'box)
        None

    :actor Main
      :new
        Example.new.call(String.new, "", "")
    SOURCE

    expected = <<-MSG
    An asynchronous function must only have sendable parameters:
    from (example):2:
      :be call (a String'ref, b String'val, c String'box)
       ^~

    - this parameter type (String'ref) is not sendable:
      from (example):2:
      :be call (a String'ref, b String'val, c String'box)
                ^~~~~~~~~~~~

    - this parameter type (String'box) is not sendable:
      from (example):2:
      :be call (a String'ref, b String'val, c String'box)
                                            ^~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "complains when a constant doesn't meet the expected type" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
      :const i8 I8: 1
      :const u64 U64: 2
      :const f64 F32: 3.3
      :const str String: "Hello, World!"
      :const array_i8 Array(I8)'val: [1]
      :const array_u64 Array(U64)'val: [2]
      :const array_f32 Array(F32)'val: [3.3]
      :const array_str Array(String)'val: ["Hello", "World"]
      :const array_ref_str Array(String)'ref: ["Hello", "World"] // NOT VAL
    SOURCE

    expected = <<-MSG
    The type of a constant may only be String, a numeric type, or an immutable Array of one of these:
    from (example):11:
      :const array_ref_str Array(String)'ref: ["Hello", "World"] // NOT VAL
             ^~~~~~~~~~~~~

    - but the type is Array(String):
      from (example):11:
      :const array_ref_str Array(String)'ref: ["Hello", "World"] // NOT VAL
                           ^~~~~~~~~~~~~~~~~
    MSG

    Mare.compiler.compile([source], :infer)
      .errors.map(&.message).join("\n").should eq expected
  end

  it "tests and conveys transitively reached subtypes to the reach pass" do
    source = Mare::Source.new_example <<-SOURCE
    :trait non Exampleable
      :fun non example String

    :primitive Example
      :fun non example String: "Hello, World!"

    :actor Main
      :fun maybe_call_example (e non)
        if (e <: Exampleable) e.example
      :new
        @maybe_call_example(Example)
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    any = ctx.namespace[source]["Any"].as(Mare::Program::Type::Link)
    trait = ctx.namespace[source]["Exampleable"].as(Mare::Program::Type::Link)
    sub = ctx.namespace[source]["Example"].as(Mare::Program::Type::Link)

    any_rt = ctx.infer[any].no_args
    trait_rt = ctx.infer[trait].no_args
    sub_rt = ctx.infer[sub].no_args

    mce_t, mce_f, mce_infer =
      ctx.infer.test_simple!(ctx, source, "Main", "maybe_call_example")
    e_param = mce_f.params.not_nil!.terms.first.not_nil!
    mce_infer.resolved(ctx, e_param).single!.should eq any_rt

    any_subtypes = ctx.infer[any_rt].each_known_complete_subtype(ctx).to_a
    trait_subtypes = ctx.infer[trait_rt].each_known_complete_subtype(ctx).to_a
    sub_subtypes = ctx.infer[sub_rt].each_known_complete_subtype(ctx).to_a

    any_subtypes.should contain(sub_rt)
    any_subtypes.should contain(trait_rt)
    trait_subtypes.should contain(sub_rt)
  end

  it "resolves all matching concrete reifications of abstract functions" do
    source = Mare::Source.new_example <<-SOURCE
    :class Person
      :fun greeting
        "Hello, World"

    :trait Greeter
      :fun greeting (String | None)

    :class World
      :fun meet! (greeter Greeter)
        greeter.greeting.as!(String)

    :actor Main
      :new (env)
        try env.out.print(World.new.meet!(Person.new))
    SOURCE

    ctx = Mare.compiler.compile([source], :infer)
    ctx.errors.should be_empty

    t = ctx.namespace[source]["Person"].as(Mare::Program::Type::Link)
    rt = ctx.infer[t].no_args
    f = rt.defn(ctx).find_func!("greeting")
    f_link = f.make_link(rt.link)
    rfs = ctx.infer[f_link].each_reified_func(rt).to_a

    # Thanks to Infer#reach_additional_subtype_relationships, we expect that
    # both the box and ref reifications of this concrete function have been
    # reached, because ref is reached via the abstract Greeter'ref.greeting
    # (and box is reached always as part of normal type checking).
    rfs.map(&.receiver.cap_only.show_type).sort.should eq ["box", "ref"]
  end

  pending "complains when the yield block result doesn't match the expected type"
  pending "enforces yield properties as part of trait subtyping"
end
