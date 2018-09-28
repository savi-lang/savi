module Mare
  module AST
    struct Declare
      property head
      property body
      def initialize(@head = [] of Term, @body = [] of Term)
      end
    end
    
    alias Term = Identifier | LiteralString | Operator | Relate
    
    struct Identifier
      property value
      def initialize(@value : String)
      end
    end
    
    struct LiteralString
      property value
      def initialize(@value : String)
      end
    end
    
    struct Operator
      property value
      def initialize(@value : String)
      end
    end
    
    struct Relate
      property terms
      def initialize(@terms = [] of Term)
      end
    end
  end
end
