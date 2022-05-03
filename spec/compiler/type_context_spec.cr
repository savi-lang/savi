describe Savi::Compiler::TypeContext do
  it "complains when the type identifier couldn't be resolved" do
    source = Savi::Source.new_example <<-SOURCE
    :actor Main
      :new
        Container(String).new("Hello").string

    :class Container(A val)
      :let a A
      :new (@a)
      :fun string String
        if (A <: String) (@a | "...")

    SOURCE

    ctx = Savi.compiler.test_compile([source], :type_context)
    ctx.errors.should be_empty

    t_link = ctx.namespace[source.package]["Container"].as(Savi::Program::Type::Link)
    f_link = t_link.make_func_link_simple("string")
    func = f_link.resolve(ctx)
    type_context = ctx.type_context[f_link]

    choice = func
      .body.not_nil!
      .terms.first.as(Savi::AST::Group)
      .terms.first.as(Savi::AST::Choice)

    left_expr = choice.list[0].last.as(Savi::AST::Group).terms.first
    right_expr = choice.list[1].last.as(Savi::AST::Group).terms.first

    type_context.layer_index(choice).should eq 0
    type_context[choice].should eq type_context[0]
    type_context[choice].all_positive_conds.size.should eq 0
    type_context[choice].all_negative_conds.size.should eq 0

    type_context.layer_index(left_expr).should eq 1
    type_context[left_expr].should eq type_context[1]
    type_context[left_expr].all_positive_conds.size.should eq 1
    type_context[left_expr].all_negative_conds.size.should eq 0

    type_context.layer_index(right_expr).should eq 2
    type_context[right_expr].should eq type_context[2]
    type_context[right_expr].all_positive_conds.size.should eq 0
    type_context[right_expr].all_negative_conds.size.should eq 1
  end
end
