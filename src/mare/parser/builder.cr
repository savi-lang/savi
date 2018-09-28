require "lingo"
require "../ast"

class Mare::Parser
  class Builder
    def initialize
      @doc = AST::Document.new
      @decl = AST::Declare.new
      @targets = [] of Array(AST::Term)
    end
    
    def build(node)
      initialize
      visit(node)
      @doc
    end
    
    private def visit(node)
      handle(node, {:enter, node.name})
      node.children.each { |child| visit(child) }
      handle(node, {:exit, node.name})
    end
    
    private def handle(node, tuple)
      case tuple
      when {:enter, :decl}
        @decl = AST::Declare.new
        @doc.list << @decl
        @targets.pop if @targets.size > 0
        @targets << @decl.head
      
      when {:exit, :decl}
        @targets.pop
        @targets << @decl.body
      
      when {:enter, :ident}
        @targets.last << AST::Identifier.new(node.full_value)
      
      when {:enter, :string}
        @targets.last << AST::LiteralString.new(node.full_value)
      
      when {:enter, :integer}
        @targets.last << AST::LiteralInteger.new(node.full_value.to_u64)
      
      when {:enter, :float}
        @targets.last << AST::LiteralFloat.new(node.full_value.to_f)
      
      when {:enter, :op}
        @targets.last << AST::Operator.new(node.full_value)
      
      when {:enter, :group}
        group = AST::Group.new(node.children[0].children[0].full_value)
        @targets.last << group
        @targets << group.terms
      
      when {:exit, :group}
        @targets.pop
      
      when {:enter, :relate}
        relate = AST::Relate.new
        @targets.last << relate
        @targets << relate.terms
      
      when {:exit, :relate}
        @targets.pop
      end
    end
  end
end
