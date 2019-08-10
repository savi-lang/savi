require "pegmatite"

module Mare::AST
  alias A = Symbol | String | UInt64 | Int64 | Float64 | Array(A)
  
  class Visitor
    def visit_any?(node : Node)
      true
    end
    
    def visit_children?(node : Node)
      true
    end
    
    def visit_pre(node : Node)
      node
    end
    
    def visit(node : Node)
      node
    end
  end
  
  abstract class Node
    getter! pos
    property flags : UInt64 = 0
    
    def with_pos(pos : Source::Pos)
      @pos = pos
      self
    end
    
    def from(other : Node)
      @pos = other.pos
      self
    end
    
    def accept(visitor)
      node = self
      if visitor.visit_any?(node)
        node = visitor.visit_pre(node)
        children_accept(visitor) if visitor.visit_children?(node)
        node = visitor.visit(node)
      end
      node
    end
    
    def children_accept(visitor)
    end
  end
  
  class Document < Node
    property list
    property! source : Source
    def initialize(@list = [] of Declare)
    end
    
    def name; :doc end
    def to_a: Array(A)
      res = [name] of A
      list.each { |x| res << x.to_a }
      res
    end
    def children_accept(visitor)
      @list.map!(&.accept(visitor))
    end
  end
  
  class Declare < Node
    property doc_strings : Array(DocString)?
    property head
    property body
    def initialize(@head = [] of Term, @body = Group.new(":"))
    end
    
    def with_pos(pos : Source::Pos)
      @body.with_pos(pos)
      super
    end
    
    def name; :declare end
    def to_a: Array(A)
      res = [name] of A
      res << doc_strings.not_nil!.map(&.value) if doc_strings
      res << head.map(&.to_a)
      res << body.to_a
      res
    end
    def children_accept(visitor)
      @head.map!(&.accept(visitor))
      @body = @body.accept(visitor)
    end
    
    def keyword
      head.first.as(Identifier).value
    end
  end
  
  alias Term = DocString | Identifier \
    | LiteralString | LiteralInteger | LiteralFloat \
    | Operator | Prefix | Relate | Group \
    | FieldRead | FieldWrite | Choice | Loop | Try
  
  class DocString < Node
    property value
    def initialize(@value : String)
    end
    def name; :doc_string end
    def to_a: Array(A); [name, value] of A end
  end
  
  class Identifier < Node
    property value
    def initialize(@value : String)
    end
    def name; :ident end
    def to_a: Array(A); [name, value] of A end
  end
  
  class LiteralString < Node
    property value
    def initialize(@value : String)
    end
    def name; :string end
    def to_a: Array(A); [name, value] of A end
  end
  
  class LiteralInteger < Node
    property value
    def initialize(@value : UInt64 | Int64)
    end
    def name; :integer end
    def to_a: Array(A); [name, value] of A end
  end
  
  class LiteralFloat < Node
    property value
    def initialize(@value : Float64)
    end
    def name; :float end
    def to_a: Array(A); [name, value] of A end
  end
  
  class Operator < Node
    property value
    def initialize(@value : String)
    end
    def name; :op end
    def to_a: Array(A); [name, value] of A end
  end
  
  class Prefix < Node
    property op
    property term
    def initialize(@op : Operator, @term : Term)
    end
    
    def name; :prefix end
    def to_a; [name, op.to_a, term.to_a] of A end
    def children_accept(visitor)
      @op = @op.accept(visitor)
      @term = @term.accept(visitor)
    end
  end
  
  class Qualify < Node
    property term
    property group
    def initialize(@term : Term, @group : Group)
    end
    
    def name; :qualify end
    def to_a; [name, term.to_a, group.to_a] of A end
    def children_accept(visitor)
      @term = @term.accept(visitor)
      @group = @group.accept(visitor)
    end
  end
  
  class Group < Node
    property style
    property terms
    def initialize(@style : String, @terms = [] of Term)
    end
    
    def name; :group end
    def to_a: Array(A)
      res = [name] of A
      res << style
      terms.each { |x| res << x.to_a }
      res
    end
    def children_accept(visitor)
      @terms.map!(&.accept(visitor))
    end
  end
  
  class Relate < Node
    property lhs
    property op
    property rhs
    def initialize(@lhs : Term, @op : Operator, @rhs : Term)
    end
    
    def name; :relate end
    def to_a; [name, lhs.to_a, op.to_a, rhs.to_a] of A end
    def children_accept(visitor)
      @lhs = @lhs.accept(visitor)
      @op = @op.accept(visitor)
      @rhs = @rhs.accept(visitor)
    end
  end
  
  class FieldRead < Node
    property value
    def initialize(@value : String)
    end
    def name; :field_r end
    def to_a: Array(A); [name, value] of A end
  end
  
  class FieldWrite < Node
    property value
    property rhs
    def initialize(@value : String, @rhs : Term)
    end
    
    def name; :field_w end
    def to_a: Array(A); [name, value, rhs.to_a] of A end
    def children_accept(visitor)
      @rhs = @rhs.accept(visitor)
    end
  end
  
  class Choice < Node
    property list
    def initialize(@list : Array({Term, Term}))
    end
    
    def name; :choice end
    def to_a: Array(A)
      res = [name] of A
      list.each { |cond, body| res << [cond.to_a, body.to_a] }
      res
    end
    def children_accept(visitor)
      @list.map! { |cond, body| {cond.accept(visitor), body.accept(visitor)} }
    end
  end
  
  class Loop < Node
    property cond : Term
    property body : Term
    property else_body : Term
    
    def initialize(@cond, @body, @else_body)
    end
    
    def name; :loop end
    def to_a: Array(A)
      res = [name] of A
      res << cond.to_a
      res << body.to_a
      res << else_body.to_a
      res
    end
    def children_accept(visitor)
      @cond = cond.accept(visitor)
      @body = body.accept(visitor)
      @else_body = else_body.accept(visitor)
    end
  end
  
  class Try < Node
    property body : Term
    property else_body : Term
    
    def initialize(@body, @else_body)
    end
    
    def name; :try end
    def to_a: Array(A)
      res = [name] of A
      res << body.to_a
      res << else_body.to_a
      res
    end
    def children_accept(visitor)
      @body = body.accept(visitor)
      @else_body = else_body.accept(visitor)
    end
  end
  
  class Yield < Node
    property term : Term
    
    def initialize(@term)
    end
    
    def name; :yield end
    def to_a: Array(A)
      res = [name] of A
      res << term.to_a
      res
    end
    def children_accept(visitor)
      @term = term.accept(visitor)
    end
  end
end
