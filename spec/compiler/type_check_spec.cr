describe Mare::Compiler::TypeCheck do
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

    ctx = Mare.compiler.compile([source], :type_check)
    ctx.errors.should be_empty

    any = ctx.namespace[source]["Any"].as(Mare::Program::Type::Link)
    trait = ctx.namespace[source]["Exampleable"].as(Mare::Program::Type::Link)
    sub = ctx.namespace[source]["Example"].as(Mare::Program::Type::Link)

    any_rt = ctx.type_check[any].no_args
    trait_rt = ctx.type_check[trait].no_args
    sub_rt = ctx.type_check[sub].no_args

    mce_t, mce_f, mce_type_check =
      ctx.type_check.test_simple!(ctx, source, "Main", "maybe_call_example")
    e_param = mce_f.params.not_nil!.terms.first.not_nil!
    mce_type_check.resolved(ctx, e_param).single!.should eq any_rt

    any_subtypes = ctx.type_check[any_rt].each_known_complete_subtype(ctx).to_a
    trait_subtypes = ctx.type_check[trait_rt].each_known_complete_subtype(ctx).to_a
    sub_subtypes = ctx.type_check[sub_rt].each_known_complete_subtype(ctx).to_a

    any_subtypes.should contain(sub_rt)
    any_subtypes.should contain(trait_rt)
    trait_subtypes.should contain(sub_rt)
  end

  pending "complains when the yield block result doesn't match the expected type"
  pending "enforces yield properties as part of trait subtyping"
end
