##
# The purpose of the Verify pass is to do some various final checks before
# allowing the code to go through to CodeGen. For example, we verify here
# that function bodies that may raise an error belong to a partial function.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps temporay state (on the stack) at the per-type level.
# This pass produces no output state.
#
class Mare::Compiler::Verify < Mare::AST::Visitor
  def self.run(ctx)
    verify = new
    ctx.infer.for_non_argumented_types.each do |infer_type|
      infer_type.all_for_funcs.each do |infer_func|
        verify.run(ctx, infer_type.reified, infer_func.reified)
      end
    end
  end
  
  def run(ctx, rt, rf)
    check_function(ctx, rt, rf)
    
    rf.func.params.try(&.terms.each(&.accept(self)))
    rf.func.body.try(&.accept(self))
  end
  
  def check_function(ctx, rt, rf)
    func = rf.func
    
    if func.body.try { |body| Jumps.any_error?(body) }
      if func.has_tag?(:constructor)
        Error.at func.ident,
          "This constructor may raise an error, but that is not allowed"
      end
      
      if !Jumps.any_error?(func.ident)
        Error.at func.ident,
          "This function name needs an exclamation point "\
          "because it may raise an error", [
            {func.ident, "it should be named '#{func.ident.value}!' instead"}
          ]
      end
    end
  end
  
  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node)
    
    node
  end
  
  # Verify that each try block has at least one possible error case.
  def touch(node : AST::Try)
    unless node.body.try { |body| Jumps.any_error?(body) }
      Error.at node, "This try block is unnecessary", [
        {node.body, "the body has no possible error cases to catch"}
      ]
    end
  end
  
  def touch(node : AST::Node)
    # Do nothing for all other AST::Nodes.
  end
end
