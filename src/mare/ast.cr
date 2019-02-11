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
    property tid : UInt64 = 0
    property rid : UInt64 = 0
    @flags : UInt64 = 0
    
    def pos
      raise "this AST node doesn't have a position: #{to_a.inspect}" unless @pos
      @pos.not_nil!
    end
    
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
    
    FLAG_VALUE_NOT_NEEDED = 0x1_u64
    
    def value_not_needed?; (@flags & FLAG_VALUE_NOT_NEEDED) != 0 end
    def value_needed?;     (@flags & FLAG_VALUE_NOT_NEEDED) == 0 end
    def value_not_needed!; @flags |= FLAG_VALUE_NOT_NEEDED end
    def value_needed!;     @flags &= ~FLAG_VALUE_NOT_NEEDED end
  end
  
  class Document < Node
    property list
    def initialize(@list = [] of Declare)
    end
    
    def dup
      super.tap { |node| node.list = list.map { |d| d.dup.as(Declare) } }
    end
    
    def name; :doc end
    def to_a: Array(A)
      res = [name] of A
      list.each { |x| res << x.to_a }
      res
    end
    def children_accept(visitor)
      @list.map! { |decl| decl.accept(visitor) }
    end
  end
  
  class Declare < Node
    property head
    property body
    def initialize(@head = [] of Term, @body = Group.new(":"))
    end
    
    def dup
      super.tap { |node| node.head = @head.map(&.dup); node.body = @body.dup }
    end
    
    def with_pos(pos : Source::Pos)
      @body.with_pos(pos)
      super
    end
    
    def name; :declare end
    def to_a: Array(A)
      [name, head.map(&.to_a), body.to_a] of A
    end
    def children_accept(visitor)
      @head.map! { |term| term.accept(visitor) }
      @body = @body.accept(visitor)
    end
    
    def keyword
      head.first.as(Identifier).value
    end
  end
  
  alias Term = Identifier \
    | LiteralString | LiteralInteger | LiteralFloat \
    | Operator | Prefix | Relate | Group \
    | FieldRead | FieldWrite | Choice
  
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
    
    def dup
      super.tap { |node| node.op = @op.dup; node.term = @term.dup }
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
    
    def dup
      super.tap { |node| node.term = @term.dup; node.group = @group.dup }
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
    
    def dup
      super.tap { |node| node.terms = @terms.map(&.dup) }
    end
    
    def name; :group end
    def to_a: Array(A)
      res = [name] of A
      res << style
      terms.each { |x| res << x.to_a }
      res
    end
    def children_accept(visitor)
      @terms.map! { |x| x.accept(visitor) }
    end
  end
  
  class Relate < Node
    property lhs
    property op
    property rhs
    def initialize(@lhs : Term, @op : Operator, @rhs : Term)
    end
    
    def dup
      super.tap do |node|
        node.lhs = @lhs.dup
        node.op = @op.dup
        node.rhs = @rhs.dup
      end
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
    
    def dup
      super.tap do |node|
        node.rhs = @rhs.dup
      end
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
    
    def dup
      super.tap do |node|
        node.list = @list.map { |(a, b)| {a.dup, b.dup} }
      end
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
end
