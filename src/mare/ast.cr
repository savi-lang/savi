module Mare
  module AST
    struct Declare
      property head
      property body
      def initialize(
        @head = [] of Identifier,
        @body = [] of LiteralString)
      end
    end
    
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
  end
end
