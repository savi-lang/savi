module Savi::AST::Gather
  # Return the list of all nodes under the given node that have annotations.
  def self.annotated_nodes(ctx, node : AST::Node)
    visitor = AnnotatedNodes.new
    node.accept(ctx, visitor)
    visitor.list
  end

  class AnnotatedNodes < AST::Visitor
    getter list = [] of AST::Node

    def visit(ctx : Compiler::Context, node : AST::Node)
      list << node if node.annotations
    end
  end
end
