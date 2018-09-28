module Mare
  module AST
    alias A = Symbol | String | Array(A)
    
    struct Document
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
    
    struct Declare
      property head
      property body
      def initialize(@head = [] of Term, @body = [] of Term)
      end
      def name; :declare end
      def to_a: Array(A);  of A end
      
      def to_a: Array(A)
        [
          name,
          head.map { |x| x.to_a },
          body.map { |x| x.to_a },
        ] of A
      end
    end
    
    alias Term = Identifier | LiteralString | Operator | Relate
    
    struct Identifier
      property value
      def initialize(@value : String)
      end
      def name; :ident end
      def to_a: Array(A); [name, value] of A end
    end
    
    struct LiteralString
      property value
      def initialize(@value : String)
      end
      def name; :string end
      def to_a: Array(A); [name, value] of A end
    end
    
    struct Operator
      property value
      def initialize(@value : String)
      end
      def name; :op end
      def to_a: Array(A); [name, value] of A end
    end
    
    struct Relate
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
