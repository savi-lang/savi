##
# The purpose of the Privacy pass is to enforce the function privacy boundary.
# Functions whose identifier starts with an underscore are considered private,
# and can only be called from within the same library where they were defined.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps temporay state (on the stack) at the per-function level.
# This pass produces no output state.
#
class Mare::Compiler::Privacy < Mare::AST::Visitor
  def self.run(ctx)
    ctx.infer.for_non_argumented_types.each do |infer_type|
      infer_type.all_for_funcs.each do |infer_func|
        privacy = new(ctx, infer_func)
        infer_func.reified.func.params.try(&.accept(privacy))
        infer_func.reified.func.body.try(&.accept(privacy))
      end
    end
  end

  getter ctx : Context
  getter infer : Infer::ForFunc

  def initialize(@ctx, @infer)
  end

  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node)

    node
  end

  def visit_children?(node : AST::Group)
    # Don't visit children of groups marked by the type checker as unreachable.
    # This keeps us from trying to deal with branches of Choices that have
    # not been typechecked and thus have no call resolution for private calls.
    !infer[node]?.is_a?(Infer::Unreachable)
  end

  def touch(node : AST::Relate)
    # Only handle function calls (dot relations).
    return unless node.op.value == "."

    # Get the identifier of the function call, if there is one.
    # TODO: some earlier pass should have made this easier for us,
    # so that we could be agnostic as to whether the call had arguments or not.
    call_ident, call_args, yield_params, yield_block = AST::Extract.call(node)

    # Only handle private calls (beginning with an underscore).
    return unless call_ident && call_ident.value.starts_with?("_")

    # Get the library reference for the call site.
    call_library = call_ident.pos.source.library

    # Compare to the library reference of each function definition,
    # collecting a list of problematic definitions for this call
    # (those whose library reference isn't the same as that of the call site).
    problems = [] of {Source::Pos, String}
    infer
    .resolve(node.lhs)
    .find_callable_func_defns(infer, call_ident.value)
    .each do |(_, _, call_func)|
      call_func_pos = call_func.not_nil!.ident.pos
      if call_library != call_func_pos.source.library
        problems << {call_func_pos,
          "this is a private function from another library"}
      end
    end

    # Raise the error if there are any problems detected.
    Error.at call_ident,
      "This function call breaks privacy boundaries", problems \
        unless problems.empty?
  end

  def touch(node : AST::Node)
    # Do nothing for all other AST::Nodes.
  end
end
