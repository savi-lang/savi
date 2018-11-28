module Mare
  class Compiler::Default < Compiler
    def initialize(@program : Program)
    end
    
    def finished(context)
      context.fulfill ["doc"], @program
    end
    
    def keywords; ["actor", "class", "ffi"] end
    
    def compile(context, decl)
      case decl.keyword
      when "actor"
        t = Type.new(Program::Type.new(Program::Type::Kind::Actor, decl.head.last.as(AST::Identifier)))
        @program.types << t.type
        context.push t
      when "class"
        t = Type.new(Program::Type.new(Program::Type::Kind::Class, decl.head.last.as(AST::Identifier)))
        @program.types << t.type
        context.push t
      when "ffi"
        t = Type.new(Program::Type.new(Program::Type::Kind::FFI, decl.head.last.as(AST::Identifier)))
        @program.types << t.type
        context.push t
      end
    end
    
    class Type < Compiler
      getter type
      
      def initialize(@type : Program::Type)
      end
      
      def keywords; ["prop", "fun", "new"] end
      
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
      
      def finished(context)
        context.fulfill ["type", @type.ident.value], @type
      end
      
      def compile(context, decl)
        case decl.keyword
        when "prop"
          # TODO: common abstraction to extract decl head terms,
          # with nice error collection for reporting to the user/tool.
          head = decl.head.dup
          head.shift # discard the keyword
          ident = head.shift.as(AST::Identifier)
          ret = head.shift.as(AST::Identifier)
          
          @type.properties << Program::Property.new(ident, ret, decl.body)
        when "fun", "new"
          # TODO: common abstraction to extract decl head terms,
          # with nice error collection for reporting to the user/tool.
          head = decl.head.dup
          head.shift # discard the keyword
          ident = head.shift.as(AST::Identifier)
          params = head.shift.as(AST::Group) if head[0]?.is_a?(AST::Group)
          ret = head.shift.as(AST::Identifier) if head[0]?
          
          function = Program::Function.new(ident, params, ret, decl.body)
          context.fulfill ["fun", @type.ident.value, ident.value], function
          
          @type.functions << function
        end
      end
    end
  end
end
