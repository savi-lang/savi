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
    phrase_used_for_type = "type"

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

    pre_infer = ctx.pre_infer[f_link]
    infer = ctx.infer[f_link]

    # Maybe show the type (span) of the receiver if this is a function call.
    infer_info = pre_infer[node]?
    if infer_info.is_a? Infer::FromCall
      span = infer.called_func_receiver_span(infer_info)
      span_inner = span.inner
      messages << "This is a function call on " +
        if span_inner.is_a?(Infer::Span::Terminal)
          "type: #{span_inner.meta_type.show_type}"
        else
          # TODO: Nicer way to display a span to an end-user,
          # who likely doesn't want to look at mysterious bit arrays.
          "type span:\n#{span.pretty_inspect}"
        end
      phrase_used_for_type = "return type"
    end

    # Maybe show the type (span) of the resulting value.
    begin
      span = infer[infer_info.not_nil!]
      span_inner = span.inner
      messages << "It has an inferred " +
        if span_inner.is_a?(Infer::Span::Terminal)
          "#{phrase_used_for_type} of: #{span_inner.meta_type.show_type}"
        else
          # TODO: Nicer way to display a span to an end-user,
          # who likely doesn't want to look at mysterious bit arrays.
          "#{phrase_used_for_type} span of:\n#{span.pretty_inspect}"
        end
    rescue
      # If anything went wrong, just don't show an inferred type message.
    end

    {messages, node.pos}
  end
end
