require "lingo"

module Mare
  class Visitor < Lingo::Visitor
    property doc  : Array(AST::Declare)
    property decl : AST::Declare
    
    def initialize
      @doc = [] of AST::Declare
      @decl = AST::Declare.new
    end
    
    enter :decl do
      visitor.decl = AST::Declare.new
      visitor.doc << visitor.decl
    end
    
    enter :decl_ident do
      visitor.decl.head << AST::Identifier.new(node.full_value)
    end
    
    enter :string do
      visitor.decl.body << AST::LiteralString.new(node.full_value)
    end
  end
end
