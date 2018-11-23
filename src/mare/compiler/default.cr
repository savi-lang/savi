module Mare
  class Compiler::Default < Compiler
    def keywords; ["actor", "class"] end
    
    def compile(context, decl)
      case decl.keyword
      when "actor"
        context.push Type.new(
          Type::Kind::Actor,
          decl.head.last.as(AST::Identifier),
        )
      when "class"
        context.push Type.new(
          Type::Kind::Class,
          decl.head.last.as(AST::Identifier),
        )
      end
    end
    
    class Type < Compiler
      enum Kind
        Actor
        Class
      end
      
      getter kind : Kind
      getter ident : AST::Identifier
      
      def initialize(@kind, @ident)
        @properties = [] of Property
        @functions = [] of Function
      end
      
      def keywords; ["prop", "fun"] end
      
      # # TODO: make these into macro-like declarations that do stuff
      # {
      #   "prop" => [
      #     {:ident, :required, AST::Identifier,
      #       "the identifier to use for this property"},
      #     {:ret, :optional, AST::Identifier,
      #       "the type to use for the value of this property"},
      #   ],
      #   "fun" => [
      #     {:ident, :required, AST::Identifier,
      #       "the identifier to use for this function"},
      #     {:params, :optional, AST::Group,
      #       "the parameter specification, surrounded by parenthesis"},
      #     {:ret, :optional, AST::Identifier,
      #       "the return type to use for this function"},
      #   ],
      # }
      
      def compile(context, decl)
        case decl.keyword
        when "prop"
          # TODO: common abstraction to extract decl head terms,
          # with nice error collection for reporting to the user/tool.
          head = decl.head.dup
          head.shift # discard the keyword
          ident = head.shift.as(AST::Identifier)
          ret = head.shift.as(AST::Identifier)
          
          @properties << Property.new(ident, ret, decl.body)
        when "fun"
          # TODO: common abstraction to extract decl head terms,
          # with nice error collection for reporting to the user/tool.
          head = decl.head.dup
          head.shift # discard the keyword
          ident = head.shift.as(AST::Identifier)
          params = head.shift.as(AST::Group) if head[0]?.is_a?(AST::Group)
          ret = head.shift.as(AST::Identifier) if head[0]?
          
          function = Function.new(ident, params, ret, decl.body)
          context.fulfill ["fun", @ident.value, ident.value], function
          
          @functions << function
        end
      end
    end
    
    class Property
      getter ident : AST::Identifier
      getter ret : AST::Identifier
      getter body : Array(AST::Term)
      
      def initialize(@ident, @ret, @body)
      end
    end
    
    class Function
      getter ident : AST::Identifier
      getter params : AST::Group?
      getter ret : AST::Identifier?
      getter body : Array(AST::Term)
      
      def initialize(@ident, @params, @ret, @body)
      end
    end
  end
end
