class Mare::Compiler::Interpreter::Default < Mare::Compiler::Interpreter
  def initialize(@program : Program)
  end
  
  def finished(context)
    context.fulfill ["doc"], @program
  end
  
  def keywords; ["actor", "class", "primitive", "numeric", "ffi"] end
  
  def compile(context, decl)
    t = Type.new(Program::Type.new(decl.head.last.as(AST::Identifier)))
    
    case decl.keyword
    when "actor"
      t.type.add_tag(:actor)
      t.type.add_tag(:allocated)
    when "class"
      t.type.add_tag(:allocated)
    when "numeric"
      t.type.add_tag(:numeric)
      t.type.add_tag(:no_desc)
    when "primitive"
    when "ffi"
      t.type.add_tag(:ffi)
    end
    
    @program.types << t.type
    context.push t
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
      if @type.is_instantiable?
        # Instantiable types with no constructor get a default empty one.
        if !@type.functions.any? { |f| f.has_tag?(:constructor) }
          default = AST::Declare.new.from(@type.ident)
          default.head << AST::Identifier.new("new").from(@type.ident)
          compile(context, default)
        end
      end
      
      # Numeric types need some basic metadata attached to know the native type.
      if @type.has_tag?(:numeric)
        # TODO: better generic mechanism for default consts
        if !@type.has_func?("bit_width")
          default = AST::Declare.new.from(@type.ident)
          default.head << AST::Identifier.new("const").from(@type.ident)
          default.head << AST::Identifier.new("bit_width").from(@type.ident)
          default.head << AST::Identifier.new("U8").from(@type.ident)
          default.body.terms << AST::LiteralInteger.new(64).from(@type.ident)
          compile(context, default)
        end
        
        bit_width_func = @type.find_func!("bit_width")
        raise "numeric bit_width must be a const" \
          unless bit_width_func.has_tag?(:constant)
        
        @type.metadata[:bit_width] = bit_width_func.body.not_nil!
          .terms.last.as(AST::LiteralInteger).value.to_i32
        
        # TODO: better generic mechanism for default consts
        if !@type.has_func?("is_floating_point")
          default = AST::Declare.new.from(@type.ident)
          default.head << AST::Identifier.new("const").from(@type.ident)
          default.head << AST::Identifier.new("is_floating_point").from(@type.ident)
          default.body.terms << AST::Identifier.new("False").from(@type.ident)
          compile(context, default)
        end
        
        is_float_func = @type.find_func!("is_floating_point")
        raise "numeric is_floating_point must be a const" \
          unless is_float_func.has_tag?(:constant)
        
        is_float = is_float_func.body.not_nil!.terms.last.as(AST::Identifier).value
        raise "invalid numeric is_floating_point value" \
          unless ["True", "False"].includes?(is_float)
        
        @type.metadata[:is_floating_point] = is_float == "True"
      end
      
      context.fulfill ["type", @type.ident.value], @type
    end
    
    def compile(context, decl)
      case decl.keyword
      when "prop"
        raise "stateless types can't have properties" \
          unless @type.is_instantiable?
        
        head = decl.head.dup
        head.shift # discard the keyword
        ident = head.shift if head[0]?
        ret = head.shift.as(AST::Identifier) if head[0]?
        
        ident = AST::Identifier.new(ident.value).from(ident) \
          if ident.is_a?(AST::LiteralString)
        ident = ident.as(AST::Identifier)
        
        field_params = AST::Group.new("(").from(ident)
        field_body = decl.body
        field_body = nil if decl.body.try { |group| group.terms.size == 0 }
        field_func = Program::Function.new(ident.dup, field_params, ret.dup, field_body)
        field_func.add_tag(:hygienic)
        field_func.add_tag(:field)
        @type.functions << field_func
        
        getter_params = AST::Group.new("(").from(ident)
        getter_body = AST::Group.new(":").from(ident)
        getter_body.terms << AST::Field.new(ident.value).from(ident)
        getter_func = Program::Function.new(ident, getter_params, ret, getter_body)
        context.fulfill ["fun", @type.ident.value, ident.value], getter_func
        @type.functions << getter_func
        
        setter_ident = AST::Identifier.new("#{ident.value}=").from(ident)
        setter_param = AST::Identifier.new("value").from(ident)
        if !ret.nil?
          pair = AST::Group.new(" ").from(setter_param)
          pair.terms << setter_param
          pair.terms << ret.dup
          setter_param = pair
        end
        setter_params = AST::Group.new("(").from(ident)
        setter_params.terms << setter_param
        setter_assign = AST::Relate.new(
          AST::Field.new(ident.value).from(ident),
          AST::Operator.new("=").from(ident),
          AST::Identifier.new("value").from(ident),
        ).from(ident)
        setter_body = AST::Group.new(":").from(ident)
        setter_body.terms << setter_assign
        setter_func = Program::Function.new(setter_ident, setter_params, ret.dup, setter_body)
        context.fulfill ["fun", @type.ident.value, setter_ident.value], setter_func
        @type.functions << setter_func
      when "fun", "new"
        # TODO: common abstraction to extract decl head terms,
        # with nice error collection for reporting to the user/tool.
        head = decl.head.dup
        head.shift # discard the keyword
        ident = head.shift if head[0]?.is_a?(AST::Identifier) || head[0]?.is_a?(AST::LiteralString)
        params = head.shift.as(AST::Group) if head[0]?.is_a?(AST::Group)
        ret = head.shift.as(AST::Identifier) if head[0]?
        
        ident = AST::Identifier.new(ident.value).from(ident) \
          if ident.is_a?(AST::LiteralString)
        ident = decl.head.first if ident.nil? && decl.keyword == "new"
        ident = ident.as(AST::Identifier)
        
        body = decl.body
        body = nil if @type.has_tag?(:ffi)
        
        if decl.keyword == "new"
          # Constructors always return the self (`@`).
          # TODO: decl parse error if an explicit return type was given
          ret ||= AST::Identifier.new("@").from(ident)
          body ||= AST::Group.new(":").from(ident)
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
        
        params = AST::Group.new("(").from(ident)
        
        body = decl.body
        
        function = Program::Function.new(ident, params, ret, body)
        context.fulfill ["fun", @type.ident.value, ident.value], function
        
        function.add_tag(:constant)
        
        @type.functions << function
      end
    end
  end
end
