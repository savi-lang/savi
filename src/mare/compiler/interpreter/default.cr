class Mare::Compiler::Interpreter::Default < Mare::Compiler::Interpreter
  def initialize(@library : Program::Library)
  end

  def finished(context)
  end

  def keywords : Array(String); %w{import source alias actor class struct trait numeric enum primitive ffi} end

  @@declare_import = Witness.new([
    {
      "kind" => "keyword",
      "name" => "keyword",
      "value" => "import",
    } of String => String | Bool,
    {
      "kind" => "term",
      "name" => "path",
      "type" => "string",
    } of String => String | Bool,
    {
      "kind" => "term",
      "name" => "params",
      "type" => "params",
      "optional" => true,
    },
  ] of Hash(String, String | Bool))

  @@declare_source = Witness.new([
    {
      "kind" => "keyword",
      "name" => "keyword",
      "value" => "source",
    } of String => String | Bool,
    {
      "kind" => "term",
      "name" => "path",
      "type" => "string",
    } of String => String | Bool,
  ] of Hash(String, String | Bool))

  @@declare_alias = Witness.new([
    {
      "kind" => "keyword",
      "name" => "keyword",
      "value" => "alias",
    } of String => String | Bool,
    {
      "kind" => "term",
      "name" => "ident_maybe_with_params",
      "type" => "ident|ident+params",
    } of String => String | Bool,
  ] of Hash(String, String | Bool))

  @@declare_type = Witness.new([
    {
      "kind" => "keyword",
      "name" => "keyword",
      "value" => "actor|class|struct|trait|numeric|enum|primitive|ffi",
    } of String => String | Bool,
    {
      "kind" => "keyword",
      "name" => "cap",
      "value" => "iso|val|ref|box|tag|non",
      "optional" => true,
    } of String => String | Bool,
    {
      "kind" => "term",
      "name" => "ident_maybe_with_params",
      "type" => "ident|ident+params",
    } of String => String | Bool,
  ] of Hash(String, String | Bool))

  def compile(context, decl)
    return compile_import(context, decl) if decl.keyword == "import"
    return compile_source(context, decl) if decl.keyword == "source"
    return compile_alias(context, decl) if decl.keyword == "alias"

    data = @@declare_type.run(decl)
    keyword = data["keyword"].as(AST::Identifier)

    # Set a default default capability for this type if not given explicitly.
    data["cap"] ||= (
      cap_value =
        case keyword.value
        when "actor"     then "tag"
        when "class"     then "ref"
        when "struct"    then "ref"
        when "trait"     then "ref"
        when "numeric"   then "val"
        when "enum"      then "val"
        when "primitive" then "non"
        when "ffi"       then "non"
        else raise NotImplementedError.new(keyword)
        end
      AST::Identifier.new(cap_value).from(keyword)
    )

    ident_maybe_with_params = data["ident_maybe_with_params"]
    case ident_maybe_with_params
    when AST::Identifier
      ident = ident_maybe_with_params
      params = nil
    when AST::Qualify
      ident = ident_maybe_with_params.term.as(AST::Identifier)
      params = ident_maybe_with_params.group
    else
      raise NotImplementedError.new(ident_maybe_with_params)
    end

    t = Type.new(
      keyword.value,
      Program::Type.new(
        data["cap"].as(AST::Identifier),
        ident,
        params,
      ),
      @library,
    )

    case keyword.value
    when "actor"
      t.type.add_tag(:actor)
      t.type.add_tag(:allocated)
    when "class"
      t.type.add_tag(:allocated)
      t.type.add_tag(:simple_value) if t.type.ident.value == "CPointer" # TODO: less hacky and special-cased for this
    when "struct"
      t.type.add_tag(:pass_by_value)
      t.type.add_tag(:no_field_reassign)
    when "trait"
      t.type.add_tag(:abstract)
      t.type.add_tag(:allocated)
    when "numeric"
      t.type.add_tag(:pass_by_value)
      t.type.add_tag(:simple_value)
      t.type.add_tag(:numeric)
    when "enum"
      t.type.add_tag(:pass_by_value)
      t.type.add_tag(:simple_value)
      t.type.add_tag(:numeric)
      t.type.add_tag(:enum)
    when "primitive"
      t.type.add_tag(:singleton)
      t.type.add_tag(:ignores_cap)
    when "ffi"
      t.type.add_tag(:singleton)
      t.type.add_tag(:ignores_cap)
      t.type.add_tag(:private)
    else
    end

    @library.types << t.type
    context.push t
  end

  def compile_import(context, decl)
    data = @@declare_import.run(decl)

    @library.imports << Program::Import.new(
      data["path"].as(AST::LiteralString),
      data["params"]?.as(AST::Group?),
    )
  end

  def compile_source(context, decl)
    data = @@declare_source.run(decl)

    @library.imports << Program::Import.new(
      data["path"].as(AST::LiteralString),
      copy_sources: true
    )
  end

  def compile_alias(context, decl)
    data = @@declare_alias.run(decl)
    body = decl.body

    ident_maybe_with_params = data["ident_maybe_with_params"]
    case ident_maybe_with_params
    when AST::Identifier
      ident = ident_maybe_with_params
      params = nil
    when AST::Qualify
      ident = ident_maybe_with_params.term.as(AST::Identifier)
      params = ident_maybe_with_params.group
    else
      raise NotImplementedError.new(ident_maybe_with_params)
    end

    Error.at ident.pos, "This alias declaration needs a body "\
      "containing a single type expression to indicate what it is an alias of" \
        unless body.is_a?(AST::Group) \
          && body.terms.size == 1 \

    @library.aliases << Program::TypeAlias.new(
      ident,
      params,
      body.not_nil!.terms.first,
    )
  end

  class Type < Interpreter
    property keyword : String # TODO: read-only as getter
    getter type : Program::Type
    getter library : Program::Library
    getter members

    def initialize(@keyword, @type, @library)
      @members = [] of Program::TypeWithValue
    end

    # TODO: dedup these with the Witness mechanism.
    # TODO: be more specific (for example, `member` is only allowed for `enum`)
    def keywords : Array(String); ["is", "copies", "let", "var", "fun", "be", "new", "const", "member", "it"] end

    def finished(context)
      # Numeric types need some basic metadata attached to know the native type.
      if @keyword == "numeric" || @keyword == "enum"
        # Add "is Numeric" to the type definition so to absorb the trait.
        trait_cap = AST::Identifier.new("non").from(@type.ident)
        trait_is = AST::Identifier.new("is").from(@type.ident)
        trait_ret = AST::Identifier.new("Numeric").from(@type.ident)
        trait_func = Program::Function.new(trait_cap, trait_is, nil, trait_ret, nil)
        trait_func.add_tag(:hygienic)
        trait_func.add_tag(:is)
        trait_func.add_tag(:copies)
        @type.functions << trait_func

        # Add "copies NumericMethods" to the type definition as well.
        copy_cap = AST::Identifier.new("non").from(@type.ident)
        copy_is = AST::Identifier.new("copies").from(@type.ident)
        copy_ret = AST::Identifier.new("NumericMethods").from(@type.ident)
        copy_func = Program::Function.new(copy_cap, copy_is, nil, copy_ret, nil)
        copy_func.add_tag(:hygienic)
        copy_func.add_tag(:copies)
        @type.functions << copy_func

        # Also copy IntegerMethods, Float32Methods, or Float64Methods.
        spec_name =
          if !@type.const_bool_true?("is_floating_point")
            "IntegerMethods"
          elsif @type.const_u64_eq?("bit_width", 32)
            "Float32Methods"
          else
            "Float64Methods"
          end
        spec_cap = AST::Identifier.new("non").from(@type.ident)
        spec_is = AST::Identifier.new("copies").from(@type.ident)
        spec_ret = AST::Identifier.new(spec_name).from(@type.ident)
        spec_func = Program::Function.new(spec_cap, spec_is, nil, spec_ret, nil)
        spec_func.add_tag(:hygienic)
        spec_func.add_tag(:copies)
        @type.functions << spec_func
      end

      # An enum type gets a method for printing the name of the member.
      if @keyword == "enum"
        # Each member gets a clause in the choice.
        member_name_choices = [] of {AST::Term, AST::Term}
        @members.each do |member|
          member_name_choices << {
            # Test if this value is equal to this member.
            AST::Relate.new(
              AST::Identifier.new("@").from(member.ident),
              AST::Operator.new("==").from(member.ident),
              AST::Identifier.new(member.ident.value).from(member.ident),
            ).from(@type.ident),
            # If true, then the value is the string literal for that member.
            AST::LiteralString.new(member.ident.value).from(member.ident),
          }
        end
        # Otherwise, the member name is returned as an empty string. Sad.
        member_name_choices << {
          AST::Identifier.new("True").from(@type.ident),
          AST::LiteralString.new("").from(@type.ident),
        }

        # Create a function body containing that choice as its only expression.
        member_name_body = AST::Group.new(":").from(@type.ident)
        member_name_body.terms <<
          AST::Choice.new(member_name_choices).from(@type.ident)

        # Finally, create a function with that body.
        member_name_func = Program::Function.new(
          AST::Identifier.new("box").from(@type.ident),
          AST::Identifier.new("member_name").from(@type.ident),
          nil,
          AST::Identifier.new("String").from(@type.ident),
          member_name_body,
        )
        @type.functions << member_name_func
      end

      # An enum type gets a method for converting from U64.
      if @keyword == "enum"
        # Each member gets a clause in the choice.
        from_u64_choices = [] of {AST::Term, AST::Term}
        @members.each do |member|
          from_u64_choices << {
            # Test if this value is equal to this member.
            AST::Relate.new(
              AST::Relate.new(
                AST::Identifier.new(member.ident.value).from(member.ident),
                AST::Operator.new(".").from(member.ident),
                AST::Identifier.new("u64").from(member.ident),
              ).from(@type.ident),
              AST::Operator.new("==").from(member.ident),
              AST::Identifier.new("value").from(member.ident),
            ).from(@type.ident),
            # If true, then the member is returned.
            AST::Identifier.new(member.ident.value).from(member.ident),
          }
        end
        # Otherwise, an error is raised. Sad.
        from_u64_choices << {
          AST::Identifier.new("True").from(@type.ident),
          AST::Jump.new(AST::Identifier.new("None").from(@type.ident),
            AST::Jump::Kind::Error).from(@type.ident),
        }

        # Create function parameters for the value parameter.
        from_u64_params = AST::Group.new("(").from(@type.ident)
        from_u64_params.terms <<
          AST::Identifier.new("value").from(@type.ident)

        # Create a function body containing that choice as its only expression.
        from_u64_body = AST::Group.new(":").from(@type.ident)
        from_u64_body.terms <<
          AST::Choice.new(from_u64_choices).from(@type.ident)

        # Finally, create a function with that body.
        from_u64_func = Program::Function.new(
          AST::Identifier.new("non").from(@type.ident),
          AST::Identifier.new("from_u64!").from(@type.ident),
          from_u64_params,
          AST::Identifier.new(@type.ident.value).from(@type.ident),
          from_u64_body,
        )
        @type.functions << from_u64_func
      end

      # An FFI type's functions should be tagged as "ffi" and body removed.
      if @keyword == "ffi"
        @type.functions.each do |f|
          f.add_tag(:ffi)
          ffi_link_name = f.ident.value
          ffi_link_name = ffi_link_name[0...-1] if ffi_link_name.ends_with?("!")
          f.metadata[:ffi_link_name] = ffi_link_name
          f.body = nil
        end
      end

      # A trait's functions should have their body removed.
      if @keyword == "trait"
        @type.functions.each do |f|
          f.body = nil if f.body.try(&.terms).try(&.empty?)
        end
      end
    end

    # TODO: This witness should be declared by the spec package.
    @@declare_it = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "it",
      } of String => String | Bool,
      {
        "kind" => "term",
        "name" => "name",
        "type" => "string",
        "convert_string_to_ident" => true,
      },
    ] of Hash(String, String | Bool))

    @@declare_fun = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "fun",
      } of String => String | Bool,
      {
        "kind" => "keyword",
        "name" => "cap",
        "value" => "iso|val|ref|box|tag|non",
        "optional" => true,
      },
      {
        "kind" => "term",
        "name" => "ident_maybe_with_params",
        "type" => "ident|string|ident+params|string+params",
        "convert_string_to_ident" => true,
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
      } of String => String | Bool,
      { # This cap isn't actually allowed for a behaviour declaration;
        # it is only accepted here so that we can give a nicer error later.
        "kind" => "keyword",
        "name" => "cap",
        "value" => "iso|val|ref|box|tag|non",
        "optional" => true,
      },
      {
        "kind" => "term",
        "name" => "ident_maybe_with_params",
        "type" => "ident|string|ident+params|string+params",
        "convert_string_to_ident" => true,
      },
    ] of Hash(String, String | Bool))

    @@declare_new = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "new",
      } of String => String | Bool,
      {
        "kind" => "keyword",
        "name" => "cap",
        "value" => "iso|val|ref|box|tag|non",
        "optional" => true,
      },
      {
        "kind" => "term",
        "name" => "ident_and_or_params",
        "type" => "ident|string|ident+params|string+params|params",
        "convert_string_to_ident" => true,
        "optional" => true,
        "default_copy_term" => "keyword",
      },
    ] of Hash(String, String | Bool))

    @@declare_const = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "const",
      } of String => String | Bool,
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

    @@declare_let = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "let",
      } of String => String | Bool,
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

    @@declare_var = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "var",
      } of String => String | Bool,
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
      } of String => String | Bool,
      {
        "kind" => "term",
        "name" => "trait",
        "type" => "type",
      } of String => String | Bool,
    ] of Hash(String, String | Bool))

    @@declare_copies = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "copies",
      } of String => String | Bool,
      {
        "kind" => "term",
        "name" => "trait",
        "type" => "type",
      } of String => String | Bool,
    ] of Hash(String, String | Bool))

    @@declare_member = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "member",
      } of String => String | Bool,
      {
        "kind" => "term",
        "name" => "ident",
        "type" => "ident",
      } of String => String | Bool,
    ] of Hash(String, String | Bool))

    def compile(context, decl)
      func = nil

      case decl.keyword
      when "it"
        data = @@declare_it.run(decl)

        func = Program::Function.new(
          AST::Identifier.new("ref").from(data["keyword"]),
          data["name"].as(AST::Identifier),
          nil,
          AST::Identifier.new("None").from(data["keyword"]),
          decl.body,
        ).tap(&.add_tag(:it))
      when "fun"
        data = @@declare_fun.run(decl)

        data["cap"] ||=
          begin
            if @type.has_tag?(:ignores_cap)
              AST::Identifier.new("non").from(data["keyword"])
            else
              AST::Identifier.new("box").from(data["keyword"])
            end
          end

        ident_maybe_with_params = data["ident_maybe_with_params"]
        case ident_maybe_with_params
        when AST::Identifier
          ident = ident_maybe_with_params
          params = nil
        when AST::Qualify
          ident = ident_maybe_with_params.term.as(AST::Identifier)
          params = ident_maybe_with_params.group
        else
          raise NotImplementedError.new(ident_maybe_with_params)
        end

        func = Program::Function.new(
          data["cap"].as(AST::Identifier),
          ident,
          params,
          data["ret"]?.as(AST::Term?),
          decl.body,
        )
      when "be"
        raise "only actors can have behaviours" \
          unless @type.has_tag?(:actor) || @type.has_tag?(:abstract)

        data = @@declare_be.run(decl)

        cap = data["cap"]?
        Error.at cap, "A behaviour can't have an explicit receiver capability" \
          if cap

        ident_maybe_with_params = data["ident_maybe_with_params"]
        case ident_maybe_with_params
        when AST::Identifier
          ident = ident_maybe_with_params
          params = nil
        when AST::Qualify
          ident = ident_maybe_with_params.term.as(AST::Identifier)
          params = ident_maybe_with_params.group
        else
          raise NotImplementedError.new(ident_maybe_with_params)
        end

        func = Program::Function.new(
          AST::Identifier.new("ref").from(data["keyword"]),
          ident,
          params,
          AST::Identifier.new("None").from(ident),
          decl.body,
        ).tap(&.add_tag(:async))
      when "new"
        Error.at decl.head.first, "stateless types can't have constructors" \
          if @type.has_tag?(:simple_value) || @type.has_tag?(:ignores_cap)

        data = @@declare_new.run(decl)

        data["cap"] ||= @type.cap.dup

        ident_and_or_params = data["ident_and_or_params"]
        case ident_and_or_params
        when AST::Identifier
          ident = ident_and_or_params
          params = nil
        when AST::Qualify
          ident = ident_and_or_params.term.as(AST::Identifier)
          params = ident_and_or_params.group
        when AST::Group
          ident_value = data["keyword"].as(AST::Identifier).value
          ident = AST::Identifier.new(ident_value).from(data["keyword"])
          params = ident_and_or_params
        else
          raise NotImplementedError.new(ident_and_or_params)
        end

        func = Program::Function.new(
          data["cap"].as(AST::Identifier),
          ident,
          params,
          AST::Identifier.new("@").from(ident),
          decl.body,
        ).tap do |f|
          f.add_tag(:constructor)
          f.add_tag(:async) if @type.has_tag?(:actor)
        end
      when "const"
        data = @@declare_const.run(decl)

        func = Program::Function.new(
          AST::Identifier.new("non").from(data["keyword"]),
          data["ident"].as(AST::Identifier),
          nil,
          data["ret"]?.as(AST::Term?),
          decl.body,
        ).tap(&.add_tag(:constant))
      when "let", "var"
        Error.at decl.head.first, "stateless types can't have properties" \
          if @type.has_tag?(:simple_value) || @type.has_tag?(:ignores_cap)

        is_let = decl.keyword == "let"

        Error.at decl.head.first,
          "This type can't have any reassignable fields; use `let` here" \
          if !is_let && @type.has_tag?(:no_field_reassign)

        data = (is_let ? @@declare_let : @@declare_var).run(decl)
        ident = data["ident"].as(AST::Identifier)
        ret = data["ret"]?.as(AST::Term?)

        field_cap = AST::Identifier.new("box").from(data["keyword"])
        field_params = AST::Group.new("(").from(ident)
        field_body = decl.body
        field_body = nil if decl.body.try { |group| group.terms.size == 0 }
        field_func = Program::Function.new(field_cap, ident.dup, field_params, ret.dup, field_body)
        field_func.add_tag(:hygienic)
        field_func.add_tag(:field)
        field_func.add_tag(:let) if is_let
        func = field_func

        getter_cap = AST::Identifier.new("box").from(data["keyword"])
        if ret
          getter_ret = AST::Relate.new(
            AST::Identifier.new("@").from(getter_cap),
            AST::Operator.new("->").from(getter_cap),
            AST::Relate.new(
              ret,
              AST::Operator.new("'").from(getter_cap),
              AST::Identifier.new("aliased").from(getter_cap),
            ).from(ret)
          ).from(ret)
        end
        getter_body = AST::Group.new(":").from(ident)
        getter_body.terms << AST::FieldRead.new(ident.value).from(ident)
        getter_func = Program::Function.new(getter_cap, ident, nil, getter_ret, getter_body)
        getter_func.add_tag(:let) if is_let
        @type.functions << getter_func

        setter_cap = AST::Identifier.new("ref").from(data["keyword"])
        setter_ident = AST::Identifier.new("#{ident.value}=").from(ident)
        setter_param = AST::Identifier.new("value").from(ident)
        if !ret.nil?
          pair = AST::Relate.new(
            setter_param,
            AST::Operator.new("EXPLICITTYPE").from(setter_param),
            ret.dup,
          ).from(setter_param)
          setter_param = pair
        end
        setter_params = AST::Group.new("(").from(ident)
        setter_params.terms << setter_param
        setter_ret = getter_ret
        setter_assign = AST::FieldWrite.new(
          ident.value,
          AST::Prefix.new(
            AST::Operator.new("--").from(ident),
            AST::Identifier.new("value").from(ident),
          ).from(ident)
        ).from(ident)
        setter_body = AST::Group.new(":").from(ident)
        setter_body.terms << setter_assign
        setter_body.terms << AST::FieldRead.new(ident.value).from(ident)
        setter_func = Program::Function.new(setter_cap, setter_ident, setter_params, setter_ret, setter_body)
        setter_func.add_tag(:let) if is_let
        @type.functions << setter_func

        displace_cap = AST::Identifier.new("ref").from(data["keyword"])
        displace_ident = AST::Identifier.new("#{ident.value}<<=").from(ident)
        displace_param = AST::Identifier.new("value").from(ident)
        if !ret.nil?
          pair = AST::Relate.new(
            displace_param,
            AST::Operator.new("EXPLICITTYPE").from(displace_param),
            ret.dup,
          ).from(displace_param)
          displace_param = pair
        end
        displace_params = AST::Group.new("(").from(ident)
        displace_params.terms << displace_param
        if ret
          displace_ret = AST::Relate.new(
            AST::Identifier.new("@").from(displace_cap),
            AST::Operator.new("->").from(displace_cap),
            ret
          ).from(ret)
        end
        displace_assign = AST::FieldDisplace.new(
          ident.value,
          AST::Prefix.new(
            AST::Operator.new("--").from(ident),
            AST::Identifier.new("value").from(ident),
          ).from(ident)
        ).from(ident)
        displace_body = AST::Group.new(":").from(ident)
        displace_body.terms << displace_assign
        displace_func = Program::Function.new(displace_cap, displace_ident, displace_params, displace_ret, displace_body)
        displace_func.add_tag(:let) if is_let
        @type.functions << displace_func
      when "is"
        data = @@declare_is.run(decl)

        func = Program::Function.new(
          AST::Identifier.new("non").from(data["keyword"]),
          decl.head.first.as(AST::Identifier),
          nil,
          data["trait"].as(AST::Term),
          nil,
        ).tap(&.add_tag(:hygienic)).tap(&.add_tag(:is)).tap(&.add_tag(:copies))
      when "copies"
        data = @@declare_copies.run(decl)

        func = Program::Function.new(
          AST::Identifier.new("non").from(data["keyword"]),
          decl.head.first.as(AST::Identifier),
          nil,
          data["trait"].as(AST::Term),
          nil,
        ).tap(&.add_tag(:hygienic)).tap(&.add_tag(:copies))
      when "member"
        raise "only enums can have members" unless @keyword == "enum"

        data = @@declare_member.run(decl)
        ident = data["ident"].as(AST::Identifier)
        body = decl.body

        raise "member value must be a single integer" \
          unless body.is_a?(AST::Group) \
            && body.terms.size == 1 \
            && body.terms[0].is_a?(AST::LiteralInteger)
        value = body.terms[0].as(AST::LiteralInteger).value.to_u64

        type_with_value =
          Program::TypeWithValue.new(ident, @type.make_link(@library), value)

        @members << type_with_value
        @library.enum_members << type_with_value
      else
      end

      if func
        @type.functions << func
        context.push Function.new(decl.keyword, func, @type, @library)
      end
    end
  end

  class Function < Interpreter
    property keyword : String # TODO: read-only as getter
    getter func : Program::Function
    getter type : Program::Type
    getter library : Program::Library

    def initialize(@keyword, @func, @type, @library)
    end

    # TODO: dedup these with the Witness mechanism.
    def keywords : Array(String); ["yields"] end

    def finished(context)
    end

    @@declare_yields = Witness.new([
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "yields",
      } of String => String | Bool,
      {
        "kind" => "term",
        "name" => "out",
        "type" => "type|params",
        "optional" => true,
        "exclude_keyword" => "for",
      },
      {
        "kind" => "keyword",
        "name" => "keyword",
        "value" => "for",
        "optional" => true, # TODO: don't accept more terms if the `for` is not here
      },
      {
        "kind" => "term",
        "name" => "in",
        "type" => "type",
        "optional" => true,
      },
    ] of Hash(String, String | Bool))

    def compile(context, decl)
      case decl.keyword
      when "yields"
        # If this yields declaration has code attached, append to the function.
        # TODO: Provide a way to declare in the interpreter that the yields
        # declaration takes no imperative code and is declarative only.
        if @func.body
          @func.body.not_nil!.terms.concat(decl.body.terms)
          decl.body.terms.clear
        else
          @func.body = AST::Group.new(decl.body.style, decl.body.terms.dup).from(decl.body)
          decl.body.terms.clear
        end

        data = @@declare_yields.run(decl)

        @func.yield_out = data["out"]?.as(AST::Term?)
        @func.yield_in  = data["in"]?.as(AST::Term?)
      else
      end
    end
  end
end
