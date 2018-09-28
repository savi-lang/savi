module Mare
  module AST
    struct Declare
      property head
      property body
      def initialize(@head = [] of Term, @body = [] of Term)
      end
    end
    
    alias Term = Identifier | LiteralString | Relate
    
    struct Identifier
      property name
      def initialize(@name : String)
      end
    end
    
    struct LiteralString
      property value
      def initialize(@value : String)
      end
    end
    
    struct Relate
      property op
      property terms
      def initialize(@op : String, @terms = [] of Term)
      end
    end
  end
end
