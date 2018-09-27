module Mare
  module AST
    alias Node = Identifier
    
    struct Identifier
      property name : String
      def initialize(@name) end
    end
  end
end
