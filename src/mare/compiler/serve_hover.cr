require "llvm"

##
# The purpose of the ServeHover pass is to serve up information about a given
# hover position in the source code, represented as a Source::Pos.
# When the [] method is called with a Source::Pos, it returns an Array(String)
# of messages describing the entity at that position, as well as an output
# Source::Pos value that points to the entirety of that entity's source.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps no state other than holding onto the Context.
# This pass produces no output state.
#
class Mare::Compiler::ServeHover
  getter! ctx : Context

  def run(ctx)
    @ctx = ctx
  end

  def [](pos : Source::Pos)
    Common::FindByPos.find(ctx, pos).try do |found|
      found.reverse_path.each do |node|
        f_link = found.f_link.not_nil! # TODO: accept non-function expressions

        messages, pos = self[f_link, node]
        return {messages, pos} unless messages.empty?
      end
    end

    {[] of String, pos}
  end

  def [](f_link : Program::Function::Link, node : AST::Node)
    messages = [] of String

    refer = ctx.refer[f_link]
    type_check = ctx.type_check.for_func_simple(ctx, f_link.type, f_link)
    describe_type = "type"

    ref = refer[node]?
    case ref
    when Refer::Self
      messages << "This refers to the current 'self' value " \
                "(the instance of the type that implements this method)."
    # TODO: FIX Error raise
    # when Refer::RaiseError
    #   messages << "This raises an error."
    when Refer::Field
      messages << "This refers to a field."
    when Refer::Local
      messages << "This is a local variable."
    when Refer::LocalUnion
      messages << "This is a local variable."
    when Refer::Type
      messages << "This is a type reference."
    when Refer::TypeAlias
      messages << "This is a type alias reference."
    when Refer::TypeParam
      messages << "This is a type parameter reference."
    when Refer::Unresolved
    when nil
    else raise NotImplementedError.new(ref)
    end

    type_check_info = ctx.type_check[f_link][node]?
    if node.is_a?(AST::Relate) && node.op.value == "."
      begin
        messages << "This is a function call on an inferred receiver type of " \
                    "#{type_check.analysis.resolved(ctx, node.lhs).show_type}."
      rescue
      end
    elsif type_check_info.is_a? Infer::FromCall
      type_check_info.follow_call_get_call_defns(ctx, type_check).not_nil!.each do |x, y, z|
        unless y.nil?
          messages << "This is a function call on type #{y.show_type}."
          describe_type = "return type"
          break
        end
      end
    end

    begin
      inf = type_check.analysis.resolved(ctx, node)
      messages << "It has an inferred #{describe_type} of #{inf.show_type}."
    rescue
    end

    {messages, node.pos}
  end
end
