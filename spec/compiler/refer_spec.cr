describe Mare::Compiler::Refer do
  it "returns the same output state when compiled again with same sources" do
    source = Mare::Source.new_example <<-SOURCE
    :primitive Greeting
      :fun greet (env Env):
        env.out.print("Hello, World")

    :actor Main
      :new (env)
        Greeting.greet(env)
    SOURCE

    ctx1 = Mare::Compiler.compile([source], :refer)
    ctx2 = Mare::Compiler.compile([source], :refer)

    t_link_g = ctx1.namespace[source]["Greeting"].as(Mare::Program::Type::Link)
    f_link_g = t_link_g.make_func_link_simple("greet")

    t_link_m = ctx1.namespace[source]["Main"].as(Mare::Program::Type::Link)
    f_link_m = t_link_m.make_func_link_simple("new")

    # Prove that the output states are the same.
    ctx1.refer[t_link_g].should eq ctx2.refer[t_link_g]
    ctx1.refer[f_link_g].should eq ctx2.refer[f_link_g]
    ctx1.refer[t_link_m].should eq ctx2.refer[t_link_m]
    ctx1.refer[f_link_m].should eq ctx2.refer[f_link_m]
  end

  it "fails to resolve a local when it was declared in another branch" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        if True (
          x = "example"
        |
          x
        )
    SOURCE

    ctx = Mare::Compiler.compile([source], :refer)

    main = ctx.namespace.main_type!(ctx)
    func = main.resolve(ctx).find_func!("new")
    func_link = func.make_link(main)
    refer = ctx.refer[func_link]
    x = func
      .body.not_nil!
      .terms.first.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Choice)
      .list.last.last.as(Mare::AST::Group)
      .terms.first

    refer[x].class.should eq Mare::Compiler::Refer::Unresolved
  end

  it "resolves a local declared in all prior branches" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        if True (
          if True (
            x = "one"
          |
            x = "two"
          )
        |
          x = "three"
        )
        x
    SOURCE

    ctx = Mare::Compiler.compile([source], :refer)

    main = ctx.namespace.main_type!(ctx)
    func = main.resolve(ctx).find_func!("new")
    func_link = func.make_link(main)
    refer = ctx.refer[func_link]
    choice_outer = func
      .body.not_nil!
      .terms.first.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Choice)

    choice_inner = choice_outer
      .list[0].last.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Choice)

    x1 = choice_inner
      .list[0].last.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Relate)
      .lhs.as(Mare::AST::Identifier)

    x2 = choice_inner
      .list[1].last.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Relate)
      .lhs.as(Mare::AST::Identifier)

    x3 = choice_outer
      .list[1].last.as(Mare::AST::Group)
      .terms.first.as(Mare::AST::Relate)
      .lhs.as(Mare::AST::Identifier)

    x = func
      .body.not_nil!
      .terms[1].as(Mare::AST::Identifier)

    refer[x].as(Mare::Compiler::Refer::LocalUnion).list.should eq [
      refer[x1].as(Mare::Compiler::Refer::Local),
      refer[x2].as(Mare::Compiler::Refer::Local),
      refer[x3].as(Mare::Compiler::Refer::Local),
    ]
  end

  it "complains when referencing a local declared in only some branches" do
    source = Mare::Source.new_example <<-SOURCE
    :actor Main
      :new
        if True (
          if True (
            // missing x
          |
            x = "two"
          )
        |
          x = "three"
        )
        x
    SOURCE

    expected = <<-MSG
    This variable can't be used here; it was assigned a value in some but not all branches:
    from (example):12:
        x
        ^

    - it was assigned here:
      from (example):7:
            x = "two"
            ^

    - it was assigned here:
      from (example):10:
          x = "three"
          ^

    - but there were other possible branches where it wasn't assigned
    MSG

    expect_raises Mare::Error, expected do
      Mare::Compiler.compile([source], :refer)
    end
  end

  it "allows the use of branch-scoped variables to assign to outer ones" do
    source = Mare::Source.new_example <<-SOURCE
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

    Mare::Compiler.compile([source], :refer)
  end

  pending "complains when a local variable name ends with an exclamation"
  pending "complains when a parameter name ends with an exclamation"
end
