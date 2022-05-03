describe Savi::Compiler::Refer do
  it "returns the same output state when compiled again with same sources" do
    source = Savi::Source.new_example <<-SOURCE
    :module Greeting
      :fun greet(env Env):
        env.out.print("Hello, World")

    :actor Main
      :new (env)
        Greeting.greet(env)
    SOURCE

    ctx1 = Savi.compiler.test_compile([source], :refer)
    ctx2 = Savi.compiler.test_compile([source], :refer)

    t_link_g = ctx1.namespace[source.package]["Greeting"].as(Savi::Program::Type::Link)
    f_link_g = t_link_g.make_func_link_simple("greet")

    t_link_m = ctx1.namespace[source.package]["Main"].as(Savi::Program::Type::Link)
    f_link_m = t_link_m.make_func_link_simple("new")

    # Prove that the output states are the same.
    ctx1.refer[t_link_g].should eq ctx2.refer[t_link_g]
    ctx1.refer[f_link_g].should eq ctx2.refer[f_link_g]
    ctx1.refer[t_link_m].should eq ctx2.refer[t_link_m]
    ctx1.refer[f_link_m].should eq ctx2.refer[f_link_m]
  end

  it "allows the use of branch-scoped variables to assign to outer ones" do
    source = Savi::Source.new_example <<-SOURCE
    :actor Main
      :new
        outer = ""
        array = ["foo", "bar", "baz"]
        array.each -> (string|
          if (string == "foo") (
            thing = string
            outer = thing
          )
        )
    SOURCE

    Savi.compiler.test_compile([source], :refer)
  end

  it "won't confuse method names as being occurrences of a local variable" do
    source = Savi::Source.new_example <<-SOURCE
    :actor Main
      :new (env Env)
        example = "example"
        @example
        env.example
    SOURCE

    ctx = Savi.compiler.test_compile([source], :refer)
    ctx.errors.should be_empty

    main = ctx.namespace.main_type!(ctx)
    func = main.resolve(ctx).find_func!("new")
    func_link = func.make_link(main)
    refer = ctx.refer[func_link]
    body = func.body.not_nil!.terms
    example_1 = body[0].as(Savi::AST::Relate).lhs.as(Savi::AST::Identifier)
    example_2 = body[1].as(Savi::AST::Call).ident
    example_3 = body[2].as(Savi::AST::Call).ident

    refer[example_1].class.should eq Savi::Compiler::Refer::Local
    refer[example_2].class.should eq Savi::Compiler::Refer::Unresolved
    refer[example_3].class.should eq Savi::Compiler::Refer::Unresolved
  end

  pending "complains when a local variable name ends with an exclamation"
  pending "complains when a parameter name ends with an exclamation"
end
