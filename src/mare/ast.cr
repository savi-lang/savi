require "pegmatite"

module Mare
  module AST
    alias A = Symbol | String | UInt64 | Float64 | Array(A)
    
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
      property tid : UInt64 = 0
      property rid : UInt64 = 0
      
      def with_pos(source : Source, token : Pegmatite::Token)
        @pos = SourcePos.new(source, token[1], token[2])
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
      def initialize(@list = [] of Declare)
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
      | Operator | Prefix | Relate | Group
    
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
      def initialize(@value : UInt64)
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
        @terms.map! { |x| x.accept(visitor) }
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
  end
end
