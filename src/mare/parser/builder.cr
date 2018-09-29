require "lingo"
require "../ast"

class Mare::Parser
  class Builder
    def initialize
      @doc = AST::Document.new
      @decl = AST::Declare.new
      @targets = [] of Array(AST::Term)
      @source = Source.none
    end
    
    def build(source, node)
      initialize
      @source = source
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
        @decl = AST::Declare.new.with_pos(@source, node)
        @doc.list << @decl
        @targets.pop if @targets.size > 0
        @targets << @decl.head
      
      when {:exit, :decl}
        @targets.pop
        @targets << @decl.body
      
      when {:enter, :ident}
        value = node.full_value
        @targets.last << AST::Identifier.new(value).with_pos(@source, node)
      
      when {:enter, :string}
        value = node.full_value
        @targets.last << AST::LiteralString.new(value).with_pos(@source, node)
      
      when {:enter, :integer}
        value = node.full_value.to_u64
        @targets.last << AST::LiteralInteger.new(value).with_pos(@source, node)
      
      when {:enter, :float}
        value = node.full_value.to_f
        @targets.last << AST::LiteralFloat.new(value).with_pos(@source, node)
      
      when {:enter, :op}
        value = node.full_value
        @targets.last << AST::Operator.new(value).with_pos(@source, node)
      
      when {:enter, :prefix}
        placeholder = AST::Operator.new("") # replace this later
        prefix = AST::Prefix.new(placeholder).with_pos(@source, node)
        @targets.last << prefix
        @targets << prefix.terms
      
      when {:exit, :prefix}
        terms = @targets.pop
        prefix = @targets.last.pop.as(AST::Prefix)
        prefix.op = terms.shift.as(AST::Operator)
        @targets.last << prefix
      
      when {:enter, :group}
        style = node.children[0].children[0].full_value
        group = AST::Group.new(style).with_pos(@source, node)
        @targets.last << group
        @targets << group.terms
      
      when {:exit, :group}
        @targets.pop
      
      when {:enter, :relate}
        relate = AST::Relate.new.with_pos(@source, node)
        @targets.last << relate
        @targets << relate.terms
      
      when {:exit, :relate}
        @targets.pop
      end
    end
  end
end
