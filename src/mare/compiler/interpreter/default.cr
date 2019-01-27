class Mare::Compiler::Interpreter::Default < Mare::Compiler::Interpreter
  def initialize(@program : Program)
  end
  
  def finished(context)
    context.fulfill ["doc"], @program
  end
  
  def keywords; ["actor", "class", "primitive", "numeric", "ffi", "interface"] end
  
  def compile(context, decl)
    keyword = decl.keyword
    t = Type.new(keyword, Program::Type.new(decl.head.last.as(AST::Identifier)))
    
    case keyword
    when "actor"
      t.type.add_tag(:actor)
      t.type.add_tag(:allocated)
    when "class"
      t.type.add_tag(:allocated)
    when "interface"
      t.type.add_tag(:abstract)
      t.type.add_tag(:allocated)
    when "numeric"
      t.type.add_tag(:numeric)
      t.type.add_tag(:no_desc)
    when "primitive"
      # no type-level tags
    when "ffi"
      # no type-level tags
    end
    
    @program.types << t.type
    context.push t
  end
  
  class Type < Interpreter
    getter keyword : String
    getter type : Program::Type
    
    def initialize(@keyword, @type)
    end
    
    # TODO: dedup these with the Witness mechanism.
    def keywords; ["prop", "fun", "new", "const"] end
    
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
      if @keyword == "numeric"
        # Add "is Numeric" to the type definition so to absorb the interface.
        iface_is = AST::Identifier.new("is").from(@type.ident)
        iface_ret = AST::Identifier.new("Numeric").from(@type.ident)
        iface_func = Program::Function.new(iface_is, nil, iface_ret, nil)
        iface_func.add_tag(:hygienic)
        iface_func.add_tag(:is)
        @type.functions << iface_func
        
        # Capture bit_width constant value, or set a default if needed.
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
        
        # Capture is_floating_point constant value, or set a default if needed.
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
      
      # An FFI type's functions should be tagged as "ffi" and body removed.
      if @keyword == "ffi"
        @type.functions.each do |f|
          f.add_tag(:ffi)
          f.body = nil
        end
      end
      
      # An interface's functions should have their body removed.
      if @keyword == "interface"
        @type.functions.each do |f|
          f.body = nil if f.body.try(&.terms).try(&.empty?)
        end
      end
    end
    
    @@declare_fun = Witness.new([
      {
        "kind" => "keyword",
        "name" => "fun",
      },
      {
        "kind" => "term",
        "name" => "ident",
        "type" => "ident|string",
        "convert_string_to_ident" => true,
      },
      {
        "kind" => "term",
        "name" => "params",
        "type" => "params",
        "optional" => true,
      },
      {
        "kind" => "term",
        "name" => "ret",
        "type" => "type",
        "optional" => true,
      },
    ] of Hash(String, String | Bool))
    
    @@declare_new = Witness.new([
      {
        "kind" => "keyword",
        "name" => "new",
      },
      {
        "kind" => "term",
        "name" => "ident",
        "type" => "ident|string",
        "convert_string_to_ident" => true,
        "optional" => true,
        "default_copy_term" => "new",
      },
      {
        "kind" => "term",
        "name" => "params",
        "type" => "params",
        "optional" => true,
      },
      {
        "kind" => "term",
        "name" => "ret",
        "type" => "type",
        "optional" => true,
      },
    ] of Hash(String, String | Bool))
    
    @@declare_const = Witness.new([
      {
        "kind" => "keyword",
        "name" => "const",
      },
      {
        "kind" => "term",
        "name" => "ident",
        "type" => "ident|string",
        "convert_string_to_ident" => true,
      },
      {
        "kind" => "term",
        "name" => "ret",
        "type" => "type",
        "optional" => true,
      },
    ] of Hash(String, String | Bool))
    
    @@declare_prop = Witness.new([
      {
        "kind" => "keyword",
        "name" => "prop",
      },
      {
        "kind" => "term",
        "name" => "ident",
        "type" => "ident|string",
        "convert_string_to_ident" => true,
      },
      {
        "kind" => "term",
        "name" => "ret",
        "type" => "type",
        "optional" => true,
      },
    ] of Hash(String, String | Bool))
    
    def compile(context, decl)
      case decl.keyword
      when "fun"
        data = @@declare_fun.run(decl)
        
        @type.functions << Program::Function.new(
          data["ident"].as(AST::Identifier),
          data["params"]?.as(AST::Group?),
          data["ret"]?.as(AST::Identifier?),
          decl.body,
        )
      when "new"
        data = @@declare_new.run(decl)
        ident = data["ident"].as(AST::Identifier)
        
        # A constructor always returns the self at the end of its body.
        body = decl.body
        body ||= AST::Group.new(":").from(ident)
        body.terms << AST::Identifier.new("@").from(ident)
        
        @type.functions << Program::Function.new(
          ident,
          data["params"]?.as(AST::Group?),
          AST::Identifier.new("@").from(ident),
          body,
        ).tap(&.add_tag(:constructor))
      when "const"
        data = @@declare_const.run(decl)
        
        @type.functions << Program::Function.new(
          data["ident"].as(AST::Identifier),
          nil,
          data["ret"]?.as(AST::Identifier?),
          decl.body,
        ).tap(&.add_tag(:constant))
      when "prop"
        raise "stateless types can't have properties" \
          unless @type.is_instantiable?
        
        data = @@declare_prop.run(decl)
        ident = data["ident"].as(AST::Identifier)
        ret = data["ret"]?.as(AST::Identifier?)
        
        field_params = AST::Group.new("(").from(ident)
        field_body = decl.body
        field_body = nil if decl.body.try { |group| group.terms.size == 0 }
        field_func = Program::Function.new(ident.dup, field_params, ret.dup, field_body)
        field_func.add_tag(:hygienic)
        field_func.add_tag(:field)
        @type.functions << field_func
        
        getter_body = AST::Group.new(":").from(ident)
        getter_body.terms << AST::Field.new(ident.value).from(ident)
        getter_func = Program::Function.new(ident, nil, ret, getter_body)
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
        @type.functions << setter_func
      end
    end
  end
end
