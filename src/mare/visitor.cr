require "lingo"

module Mare
  class Visitor < Lingo::Visitor
    property doc
    property decl
    property targets
    
    def initialize
      @doc = [] of AST::Declare
      @decl = AST::Declare.new
      @targets = [] of Array(AST::Term)
    end
    
    def target
      targets.last
    end
    
    enter :decl do
      visitor.decl = AST::Declare.new
      visitor.doc << visitor.decl
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
    
    enter :op do
      visitor.target << AST::Operator.new(node.full_value)
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
