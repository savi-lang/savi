class Mare::Compiler::Interpreter::Default < Mare::Compiler::Interpreter
  def initialize(@program : Program)
  end
  
  def finished(context)
  end
  
  def keywords; %w{actor class interface numeric enum primitive ffi} end
  
  def compile(context, decl)
    keyword = decl.keyword
    
    # Set a default default capability for this type.
    cap_value =
      case keyword
      when "actor"     then "tag"
      when "class"     then "ref"
      when "interface" then "ref"
      when "numeric"   then "val"
      when "enum"      then "val"
      when "primitive" then "non"
      when "ffi"       then "non"
      else raise NotImplementedError.new(keyword)
      end
    cap = AST::Identifier.new(cap_value).from(decl.head.first.not_nil!)
    
    # Get the explicit default capability for this type.
    cap = decl.head[1]?.as(AST::Identifier) \
      if decl.head.size > 2 && cap_value == "ref"
    
    t = Type.new(
      keyword,
      Program::Type.new(cap, decl.head.last.as(AST::Identifier)),
      @program,
    )
    
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
    when "enum"
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
    property keyword : String # TODO: read-only as getter
    getter type : Program::Type
    getter program : Program
    
    def initialize(@keyword, @type, @program)
    end
    
    # TODO: dedup these with the Witness mechanism.
    # TODO: be more specific (for example, `member` is only allowed for `enum`)
    def keywords; ["is", "prop", "fun", "be", "new", "const", "member"] end
    
    def finished(context)
      if @type.is_instantiable?
        # Instantiable types with no constructor get a default empty one.
        if !@type.functions.any? { |f| f.has_tag?(:constructor) }
          default = AST::Declare.new.from(@type.ident)
          default.head << AST::Identifier.new("new").from(@type.ident)
          default.body = AST::Group.new(":").from(@type.ident)
          default.head << @type.cap.dup
          compile(context, default)
        end
      end
      
      # Numeric types need some basic metadata attached to know the native type.
      if @keyword == "numeric" || @keyword == "enum"
        # Add "is Numeric" to the type definition so to absorb the interface.
        iface_cap = AST::Identifier.new("non").from(@type.ident)
        iface_is = AST::Identifier.new("is").from(@type.ident)
        iface_ret = AST::Identifier.new("Numeric").from(@type.ident)
        iface_func = Program::Function.new(iface_cap, iface_is, nil, iface_ret, nil)
        iface_func.add_tag(:hygienic)
        iface_func.add_tag(:is)
        @type.functions << iface_func
        
        # Capture bit_width constant value, or set a default if needed.
        # TODO: better generic mechanism for default consts
        if !@type.find_func?("bit_width")
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
          .terms.last.as(AST::LiteralInteger).value
        
        # Capture is_floating_point constant value, or set a default if needed.
        # TODO: better generic mechanism for default consts
        if !@type.find_func?("is_floating_point")
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
        
        # Capture is_floating_point constant value, or set a default if needed.
        # TODO: better generic mechanism for default consts
        if !@type.find_func?("is_signed")
          default = AST::Declare.new.from(@type.ident)
          default.head << AST::Identifier.new("const").from(@type.ident)
          default.head << AST::Identifier.new("is_signed").from(@type.ident)
          default.body.terms << AST::Identifier.new("False").from(@type.ident)
          compile(context, default)
        end
        
        is_float_func = @type.find_func!("is_signed")
        raise "numeric is_signed must be a const" \
          unless is_float_func.has_tag?(:constant)
        
        is_float = is_float_func.body.not_nil!.terms.last.as(AST::Identifier).value
        raise "invalid numeric is_signed value" \
          unless ["True", "False"].includes?(is_float)
        
        @type.metadata[:is_signed] = is_float == "True"
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
        "name" => "keyword",
        "value" => "fun",
      },
      {
        "kind" => "keyword",
        "name" => "cap",
        "value" => "iso|trn|val|ref|box|tag|non",
        "optional" => true,
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
    
    @@declare_be = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "be",
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
    ] of Hash(String, String | Bool))
    
    @@declare_new = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "new",
      },
      {
        "kind" => "keyword",
        "name" => "cap",
        "value" => "iso|trn|val|ref|box|tag|non",
        "optional" => true,
      },
      {
        "kind" => "term",
        "name" => "ident",
        "type" => "ident|string",
        "convert_string_to_ident" => true,
        "optional" => true,
        "default_copy_term" => "keyword",
      },
      {
        "kind" => "term",
        "name" => "params",
        "type" => "params",
        "optional" => true,
      },
    ] of Hash(String, String | Bool))
    
    @@declare_const = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "const",
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
        "name" => "keyword",
        "value" => "prop",
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
    
    @@declare_is = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "is",
      },
      {
        "kind" => "term",
        "name" => "interface",
        "type" => "ident",
      },
    ] of Hash(String, String | Bool))
    
    @@declare_member = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "member",
      },
      {
        "kind" => "term",
        "name" => "ident",
        "type" => "ident",
      },
    ] of Hash(String, String | Bool))
    
    def compile(context, decl)
      case decl.keyword
      when "fun"
        data = @@declare_fun.run(decl)
        
        data["cap"] ||=
          begin
            if @type.has_tag?(:allocated) ||  @type.has_tag?(:no_desc)
              AST::Identifier.new("box").from(data["keyword"])
            else
              AST::Identifier.new("non").from(data["keyword"])
            end
          end
        
        @type.functions << Program::Function.new(
          data["cap"].as(AST::Identifier),
          data["ident"].as(AST::Identifier),
          data["params"]?.as(AST::Group?),
          data["ret"]?.as(AST::Identifier?),
          decl.body,
        )
      when "be"
        raise "only actors can have behaviours" \
          unless @type.has_tag?(:actor)
        
        data = @@declare_be.run(decl)
        
        @type.functions << Program::Function.new(
          AST::Identifier.new("ref").from(data["keyword"]),
          data["ident"].as(AST::Identifier),
          data["params"]?.as(AST::Group?),
          AST::Identifier.new("None").from(data["ident"]),
          decl.body,
        ).tap(&.add_tag(:async))
      when "new"
        raise "stateless types can't have constructors" \
          unless @type.is_instantiable?
        
        data = @@declare_new.run(decl)
        
        data["cap"] ||= AST::Identifier.new("ref").from(data["keyword"])
        
        @type.functions << Program::Function.new(
          data["cap"].as(AST::Identifier),
          data["ident"].as(AST::Identifier),
          data["params"]?.as(AST::Group?),
          AST::Identifier.new("@").from(data["ident"]),
          decl.body,
        ).tap do |f|
          f.add_tag(:constructor)
          f.add_tag(:async) if @type.has_tag?(:actor)
        end
      when "const"
        data = @@declare_const.run(decl)
        
        @type.functions << Program::Function.new(
          AST::Identifier.new("non").from(data["keyword"]),
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
        
        field_cap = AST::Identifier.new("tag").from(data["keyword"])
        field_params = AST::Group.new("(").from(ident)
        field_body = decl.body
        field_body = nil if decl.body.try { |group| group.terms.size == 0 }
        field_func = Program::Function.new(field_cap, ident.dup, field_params, ret.dup, field_body)
        field_func.add_tag(:hygienic)
        field_func.add_tag(:field)
        @type.functions << field_func
        
        getter_cap = AST::Identifier.new("box").from(data["keyword"])
        getter_body = AST::Group.new(":").from(ident)
        getter_body.terms << AST::FieldRead.new(ident.value).from(ident)
        getter_func = Program::Function.new(getter_cap, ident, nil, ret, getter_body)
        @type.functions << getter_func
        
        setter_cap = AST::Identifier.new("ref").from(data["keyword"])
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
        setter_assign = AST::FieldWrite.new(
          ident.value,
          AST::Identifier.new("value").from(ident),
        ).from(ident)
        setter_body = AST::Group.new(":").from(ident)
        setter_body.terms << setter_assign
        setter_func = Program::Function.new(setter_cap, setter_ident, setter_params, ret.dup, setter_body)
        @type.functions << setter_func
      when "is"
        data = @@declare_is.run(decl)
        
        @type.functions << Program::Function.new(
          AST::Identifier.new("non").from(data["keyword"]),
          decl.head.first.as(AST::Identifier),
          nil,
          data["interface"].as(AST::Identifier),
          nil,
        ).tap(&.add_tag(:hygienic)).tap(&.add_tag(:is))
      when "member"
        raise "only enums can have members" unless @keyword == "enum"
        
        data = @@declare_member.run(decl)
        ident = data["ident"].as(AST::Identifier)
        body = decl.body
        
        raise "member value must be a single integer" \
          unless body.is_a?(AST::Group) \
            && body.terms.size == 1 \
            && body.terms[0].is_a?(AST::LiteralInteger)
        value = body.terms[0].as(AST::LiteralInteger)
        
        type_alias = Program::TypeAlias.new(ident, @type.ident.dup)
        type_alias.metadata[:enum_value] =
          body.terms[0].as(AST::LiteralInteger).value.to_i32
        
        @program.aliases << type_alias
      end
    end
  end
end
