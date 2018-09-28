require "lingo"
require "../ast"

class Mare::Parser
  class Builder < Lingo::Visitor
    property doc
    property decl
    property targets
    
    def initialize
      @doc = AST::Document.new
      @decl = AST::Declare.new
      @targets = [] of Array(AST::Term)
    end
    
    def target
      targets.last
    end
    
    enter :decl do
      visitor.decl = AST::Declare.new
      visitor.doc.list << visitor.decl
      visitor.targets.pop if visitor.targets.size > 0
      visitor.targets << visitor.decl.head
    end
    
    exit :decl do
      visitor.targets.pop
      visitor.targets << visitor.decl.body
    end
    
    enter :ident do
      visitor.target << AST::Identifier.new(node.full_value)
    end
    
    enter :string do
      visitor.target << AST::LiteralString.new(node.full_value)
    end
    
    enter :integer do
      visitor.target << AST::LiteralInteger.new(node.full_value.to_u64)
    end
    
    enter :float do
      visitor.target << AST::LiteralFloat.new(node.full_value.to_f)
    end
    
    enter :op do
      visitor.target << AST::Operator.new(node.full_value)
    end
    
    enter :group do
      group = AST::Group.new(node.children[0].children[0].full_value)
      visitor.target << group
      visitor.targets << group.terms
    end
    
    exit :group do
      visitor.targets.pop
    end
    
    enter :relate do
      relate = AST::Relate.new
      visitor.target << relate
      visitor.targets << relate.terms
    end
    
    exit :relate do
      visitor.targets.pop
    end
  end
end
