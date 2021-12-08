describe Savi::Compiler::ReferType do
  it "returns the same output state when compiled again with same sources" do
    source = Savi::Source.new_example <<-SOURCE
    :module Greeting
      :fun greet(env Env):
        env.out.print("Hello, World")

    :actor Main
      :new (env)
        Greeting.greet(env)
    SOURCE

    ctx1 = Savi.compiler.test_compile([source], :refer_type)
    ctx2 = Savi.compiler.test_compile([source], :refer_type)
    ctx1.errors.should be_empty
    ctx2.errors.should be_empty

    t_link_g = ctx1.namespace[source]["Greeting"].as(Savi::Program::Type::Link)
    f_link_g = t_link_g.make_func_link_simple("greet")

    t_link_m = ctx1.namespace[source]["Main"].as(Savi::Program::Type::Link)
    f_link_m = t_link_m.make_func_link_simple("new")

    # Prove that the output states are the same.
    ctx1.refer_type[t_link_g].should eq ctx2.refer_type[t_link_g]
    ctx1.refer_type[f_link_g].should eq ctx2.refer_type[f_link_g]
    ctx1.refer_type[t_link_m].should eq ctx2.refer_type[t_link_m]
    ctx1.refer_type[f_link_m].should eq ctx2.refer_type[f_link_m]

    # Prove that we resolved Env from the core Savi package.
    ref_Env = ctx1.refer_type[f_link_g][
      f_link_g.resolve(ctx2)
        .params.not_nil!
        .terms.first.not_nil!.as(Savi::AST::Relate)
        .rhs.not_nil!.as(Savi::AST::Identifier)
    ]
    ref_Env.as(Savi::Compiler::Refer::Type).link.name.should eq "Env"

    # Prove that we resolved Greeting from the local source.
    ref_Greeting = ctx1.refer_type[f_link_m][
      f_link_m.resolve(ctx2)
        .body.not_nil!
        .terms.first.not_nil!.as(Savi::AST::Call)
        .receiver.as(Savi::AST::Identifier)
    ]
    ref_Greeting.as(Savi::Compiler::Refer::Type).link.should eq t_link_g
  end
end
