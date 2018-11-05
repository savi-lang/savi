require "lingo"

module Mare
  module AST
    alias A = Symbol | String | UInt64 | Float64 | Array(A)
    
    abstract struct Node
      getter pos
      
      def with_pos(source : Source, node : Lingo::Node)
        size = node.full_value.size
        @pos = SourcePos.new(
          source,
          node.line,
          node.column,
          node.line, # TODO: account for newlines in node.full_value
          node.column + size)
        self
      end
    end
    
    struct Document < Node
      property list
      def initialize(@list = [] of Declare)
      end
      def name; :doc end
      def to_a: Array(A)
        res = [name] of A
        list.each { |x| res << x.to_a }
        res
      end
    end
    
    struct Declare < Node
      property head
      property body
      def initialize(@head = [] of Term, @body = [] of Term)
      end
      def name; :declare end
      def to_a: Array(A)
        [name, head.map(&.to_a), body.map(&.to_a)] of A
      end
      
      def keyword
        head.first.as(Identifier).value
      end
    end
    
    alias Term = Identifier \
      | LiteralString | LiteralInteger | LiteralFloat \
      | Operator | Prefix | Relate | Group
    
    struct Identifier < Node
      property value
      def initialize(@value : String)
      end
      def name; :ident end
      def to_a: Array(A); [name, value] of A end
    end
    
    struct LiteralString < Node
      property value
      def initialize(@value : String)
      end
      def name; :string end
      def to_a: Array(A); [name, value] of A end
    end
    
    struct LiteralInteger < Node
      property value
      def initialize(@value : UInt64)
      end
      def name; :integer end
      def to_a: Array(A); [name, value] of A end
    end
    
    struct LiteralFloat < Node
      property value
      def initialize(@value : Float64)
      end
      def name; :float end
      def to_a: Array(A); [name, value] of A end
    end
    
    struct Operator < Node
      property value
      def initialize(@value : String)
      end
      def name; :op end
      def to_a: Array(A); [name, value] of A end
    end
    
    struct Prefix < Node
      property op
      property terms
      def initialize(@op : Operator, @terms = [] of Term)
      end
      def name; :prefix end
      def to_a: Array(A)
        res = [name] of A
        res << op.to_a
        terms.each { |x| res << x.to_a }
        res
      end
    end
    
    struct Group < Node
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
    end
    
    struct Relate < Node
      property terms
      def initialize(@terms = [] of Term)
      end
      def name; :relate end
      def to_a: Array(A)
        res = [name] of A
        terms.each { |x| res << x.to_a }
        res
      end
    end
  end
end
