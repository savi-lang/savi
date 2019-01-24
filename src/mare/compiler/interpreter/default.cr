class Mare::Compiler::Interpreter::Default < Mare::Compiler::Interpreter
  def initialize(@program : Program)
  end
  
  def finished(context)
    context.fulfill ["doc"], @program
  end
  
  def keywords; ["actor", "class", "primitive", "numeric", "ffi"] end
  
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
    when "numeric"
      t = Type.new(Program::Type.new(Program::Type::Kind::Numeric, decl.head.last.as(AST::Identifier)))
      @program.types << t.type
      context.push t
    when "primitive"
      t = Type.new(Program::Type.new(Program::Type::Kind::Primitive, decl.head.last.as(AST::Identifier)))
      @program.types << t.type
      context.push t
    when "ffi"
      t = Type.new(Program::Type.new(Program::Type::Kind::FFI, decl.head.last.as(AST::Identifier)))
      @program.types << t.type
      context.push t
    end
  end
  
  class Type < Interpreter
    getter type
    
    def initialize(@type : Program::Type)
    end
    
    def keywords; ["prop", "fun", "new", "const"] end
    
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
      # Instantiable types with no constructor get a default empty one.
      if @type.is_instantiable? \
      && !@type.functions.any? { |f| f.has_tag?(:constructor) }
        default = AST::Declare.new.from(@type.ident)
        default.head << AST::Identifier.new("new").from(@type.ident)
        compile(context, default)
      end
      
      context.fulfill ["type", @type.ident.value], @type
    end
    
    def compile(context, decl)
      case decl.keyword
      when "prop"
        # TODO: common abstraction to extract decl head terms,
        # with nice error collection for reporting to the user/tool.
        head = decl.head.dup
        head.shift # discard the keyword
        ident = head.shift.as(AST::Identifier | AST::LiteralString)
        ret = head.shift.as(AST::Identifier)
        
        ident = AST::Identifier.new(ident.value).from(ident) \
          if ident.is_a?(AST::LiteralString)
        ident = ident.as(AST::Identifier)
        
        @type.properties << Program::Property.new(ident, ret, decl.body)
      when "fun", "new"
        # TODO: common abstraction to extract decl head terms,
        # with nice error collection for reporting to the user/tool.
        head = decl.head.dup
        head.shift # discard the keyword
        ident = head.shift if head[0]?
        params = head.shift.as(AST::Group) if head[0]?.is_a?(AST::Group)
        ret = head.shift.as(AST::Identifier) if head[0]?
        
        ident = AST::Identifier.new(ident.value).from(ident) \
          if ident.is_a?(AST::LiteralString)
        ident = decl.head.first if ident.nil? && decl.keyword == "new"
        ident = ident.as(AST::Identifier)
        
        body = decl.body
        body = nil if @type.kind == Program::Type::Kind::FFI
        
        if decl.keyword == "new"
          # Constructors always return the self (`@`).
          # TODO: decl parse error if an explicit return type was given
          ret ||= AST::Identifier.new("@").from(ident)
          body ||= AST::Group.new(":")
          body.terms << AST::Identifier.new("@").from(ident)
        end
        
        function = Program::Function.new(ident, params, ret, body)
        context.fulfill ["fun", @type.ident.value, ident.value], function
        
        function.add_tag(:constructor) if decl.keyword == "new"
        
        @type.functions << function
      when "const"
        # TODO: common abstraction to extract decl head terms,
        # with nice error collection for reporting to the user/tool.
        head = decl.head.dup
        head.shift # discard the keyword
        ident = head.shift if head[0]?
        ret = head.shift.as(AST::Identifier) if head[0]?
        
        ident = AST::Identifier.new(ident.value).from(ident) \
          if ident.is_a?(AST::LiteralString)
        ident = ident.as(AST::Identifier)
        
        params = AST::Group.new(":").from(ident)
        
        body = decl.body
        
        function = Program::Function.new(ident, params, ret, body)
        context.fulfill ["fun", @type.ident.value, ident.value], function
        
        function.add_tag(:constant_value)
        
        @type.functions << function
      end
    end
  end
end
