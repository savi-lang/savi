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
    
    func_body = func.body
    if func_body && Jumps.any_error?(func_body)
      if func.has_tag?(:constructor)
        finder = ErrorFinderVisitor.new(func_body)
        func_body.accept(finder)
        
        Error.at func.ident,
          "This constructor may raise an error, but that is not allowed",
          finder.found.map { |pos| {pos, "an error may be raised here"} }
      end
      
      if !Jumps.any_error?(func.ident)
        finder = ErrorFinderVisitor.new(func_body)
        func_body.accept(finder)
        
        Error.at func.ident,
          "This function name needs an exclamation point "\
          "because it may raise an error", [
            {func.ident, "it should be named '#{func.ident.value}!' instead"}
          ] + finder.found.map { |pos| {pos, "an error may be raised here"} }
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
  
  # This visitor finds the most specific source positions that may raise errors.
  class ErrorFinderVisitor < Mare::AST::Visitor
    getter found
    
    def initialize(node : AST::Node)
      @found = [] of Source::Pos
      @deepest = node
    end
    
    # Only visit nodes that may raise an error.
    def visit_any?(node)
      Jumps.any_error?(node)
    end
    
    # Before visiting a node's children, mark this node as the deepest.
    # If any children can also raise errors, they will be the new deepest ones,
    # removing this node from the possibility of being considered deepest.
    def visit_pre(node)
      @deepest = node
    end
    
    # Save this source position if it is the deepest node in this branch of
    # the tree that we visited, recognizing that we skipped no-error branches.
    def visit(node)
      @found << node.pos if @deepest == node
      
      node
    end
  end
end
