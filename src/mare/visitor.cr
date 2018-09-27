require "lingo"

module Mare
  class Visitor < Lingo::Visitor
    property doc  : Array(Array(AST::Node))
    property decl : Array(AST::Node)
    
    def initialize
      @doc = [] of Array(AST::Node)
      @decl = [] of AST::Node
    end
    
    enter :decl do
      visitor.decl = [] of AST::Node
      visitor.doc << visitor.decl
    end
    
    enter :decl_ident do
      visitor.decl << AST::Identifier.new(node.full_value)
    end
  end
end
