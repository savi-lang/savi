# This module defines the evaluation effects for all of those declarators
# whose effects are not defined in Savi code. Such declarators are tagged
# with the `:intrinsic` declaration indicating they are not defined in Savi.
#
# Eventually we may be able to refactor some of these compiler intrinsics
# such that they are definable in Savi code, based more fundamental intrinsics.
module Savi::Program::Intrinsic
  def self.run(
    ctx : Compiler::Context,
    scope : Declarator::Scope,
    declarator : Declarator,
    declare : AST::Declare,
    terms : Hash(String, AST::Term?),
  )
    case declarator.context.value

    # Declarations at the top level.
    when "top"
      case declarator.name.value
      when "declarator"
        name = terms["name"].as(AST::Identifier)
        scope.current_declarator = Declarator.new(name)
      when "manifest"
        name = terms["name"].as(AST::Identifier)
        kind = terms["kind"].as(AST::Identifier)

        scope.current_manifest = manifest =
          Packaging::Manifest.new(declare, name, kind)

        # Every manifest automatically "provides" its main name.
        manifest.provides_names << name
      when "alias"
        name, params =
          AST::Extract.name_and_params(terms["name_and_params"].not_nil!)

        type_alias = Program::TypeAlias.new(name, params)

        scope.current_package.aliases << type_alias

        scope.on_body { |body|
          unless body.terms.size == 1
            ctx.error_at body.pos,
              "The target of an alias must be a single type expression"
            next
          end

          type_alias.target = body.terms.first
        }
      when "actor", "class", "struct", "trait",
           "numeric", "enum", "module", "ffimodule"
        name, params =
          AST::Extract.name_and_params(terms["name_and_params"].not_nil!)

        type = scope.current_type = Type.new(
          terms["cap"].as(AST::Identifier),
          name,
          params,
        )

        if declarator.name.value == "enum"
          scope.current_members = [] of TypeWithValue
        end

        # TODO: Move this to the declarators, wrapping a raw_type declaration?
        case declarator.name.value
        when "actor"
          type.add_tag(:actor)
          type.add_tag(:allocated)
        when "class"
          type.add_tag(:allocated)
          type.add_tag(:simple_value) if type.ident.value == "CPointer" # TODO: less hacky and special-cased for this
        when "struct"
          type.add_tag(:pass_by_value)
          type.add_tag(:no_field_reassign)
        when "trait"
          type.add_tag(:abstract)
          type.add_tag(:allocated)
        when "numeric"
          type.add_tag(:pass_by_value)
          type.add_tag(:simple_value)
          type.add_tag(:numeric)
        when "enum"
          type.add_tag(:pass_by_value)
          type.add_tag(:simple_value)
          type.add_tag(:numeric)
          type.add_tag(:enum)
        when "module"
          type.add_tag(:singleton)
          type.add_tag(:ignores_cap)
        when "ffimodule"
          type.add_tag(:singleton)
          type.add_tag(:ignores_cap)
        else
          raise NotImplementedError.new(declarator.name.value)
        end
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within a declarator definition.
    when "declarator"
      case declarator.name.value
      when "intrinsic"
        scope.current_declarator.intrinsic = true
      when "context"
        name = terms["name"].as(AST::Identifier)
        scope.current_declarator.context = name
      when "begins"
        name = terms["name"].as(AST::Identifier).value
        scope.current_declarator.begins << name
      when "body"
        scope.current_declarator.body_allowed = true
        if terms["requirement"].as(AST::Identifier).value == "required"
          scope.current_declarator.body_required = true
        end
      when "keyword"
        keyword = terms["keyword"].as(AST::Identifier).value
        scope.current_declarator.terms <<
          Declarator::TermAcceptor::Keyword.new(declare.pos, keyword)
      when "term"
        scope.current_declarator_term =
          if declarator.terms.any?(&.name.==("possible"))
            name = terms["name"].as(AST::Identifier).value
            possible = terms["possible"].as(AST::Group)
              .terms.map(&.as(AST::Identifier).value)
            Declarator::TermAcceptor::Enum.new(declare.pos, name, possible)
          elsif declarator.terms.any?(&.name.==("type"))
            name = terms["name"].as(AST::Identifier).value
            type = terms["type"].as(AST::Identifier).value
            Declarator::TermAcceptor::Typed.new(declare.pos, name, type)
          else
            raise NotImplementedError.new(declarator.pretty_inspect)
          end
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within a declarator term definition.
    when "declarator_term"
      case declarator.name.value
      when "optional"
        scope.current_declarator_term.optional = true
      when "default"
        term = terms["term"].not_nil!
        scope.current_declarator_term.default = term
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within a manifest definition.
    when "manifest"
      case declarator.name.value
      when "copies"
        name = terms["name"].as(AST::Identifier)
        scope.current_manifest.copies_names << name
      when "sources"
        path = terms["path"].as(AST::LiteralString)
        scope.current_manifest.sources_paths << {path, [] of AST::LiteralString}
      when "dependency"
        name = terms["name"].as(AST::Identifier)
        version = terms["version"]?.try(&.as(AST::Identifier))
        scope.current_manifest_dependency = dep =
          Packaging::Dependency.new(declare, name, version)
        scope.current_manifest.dependencies << dep
      when "transitive"
        name = terms["name"].as(AST::Identifier)
        version = terms["version"]?.try(&.as(AST::Identifier))
        scope.current_manifest_dependency = dep =
          Packaging::Dependency.new(declare, name, version, transitive: true)
        scope.current_manifest.dependencies << dep
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within a manifest sources definition.
    when "manifest_sources"
      case declarator.name.value
      when "excluding"
        path = terms["path"].as(AST::LiteralString)
        scope.current_manifest.sources_paths.last.last << path
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within a manifest dependency definition.
    when "manifest_dependency"
      case declarator.name.value
      when "from"
        location = terms["location"].as(AST::LiteralString)
        scope.current_manifest_dependency.location_nodes << location
      when "lock"
        revision = terms["revision"].as(AST::Identifier)
        scope.current_manifest_dependency.revision_nodes << revision
      when "depends"
        name = terms["other"].as(AST::Identifier)
        scope.current_manifest_dependency.depends_on_nodes << name
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within a type definition.
    when "type", "type_singleton", "ffimodule"
      case declarator.name.value
      when "it"
        name = terms["name"].as(AST::LiteralString)
        function = Program::Function.new(
          AST::Identifier.new("ref").from(declare.terms.first),
          AST::Identifier.new(name.value).from(name),
          nil,
          AST::Identifier.new("None").from(declare.terms.first),
        ).tap(&.add_tag(:it))

        scope.current_type.functions << function

        scope.on_body { |body| function.body = body }
      when "fun"
        name, params =
          AST::Extract.name_and_params(terms["name_and_params"].not_nil!)

        scope.current_function = function = Program::Function.new(
          terms["cap"].as(AST::Identifier),
          name,
          params,
          terms["ret"]?.as(AST::Term?),
        )

        scope.on_body { |body| function.body = body }
      when "be"
        # TODO: Move this error to a later compiler pass?
        type = scope.current_type
        raise "only actors can have behaviours" \
          unless type.has_tag?(:actor) || type.has_tag?(:abstract)

        name, params =
          AST::Extract.name_and_params(terms["name_and_params"].not_nil!)

        scope.current_function = function = Program::Function.new(
          AST::Identifier.new("ref").from(declare.terms.first),
          name,
          params,
          AST::Identifier.new("None").from(name),
        ).tap(&.add_tag(:async))

        scope.on_body { |body| function.body = body }
      when "new"
        type = scope.current_type

        # TODO: Move this error to a later compiler pass?
        Error.at declare.terms.first, "stateless types can't have constructors" \
          if type.has_tag?(:simple_value) || type.has_tag?(:ignores_cap)

        if terms["name_and_params"]?
          name, params =
            AST::Extract.name_and_params(terms["name_and_params"].not_nil!)
        else
          name = declare.terms.first.dup.as(AST::Identifier)
          params = terms["params"]?.as(AST::Group?)
        end

        scope.current_function = function = Program::Function.new(
          terms["cap"]?.as(AST::Identifier?) || type.cap.dup,
          name,
          params,
          AST::Identifier.new("@").from(name),
        ).tap do |f|
          f.add_tag(:constructor)
          f.add_tag(:async) if type.has_tag?(:actor)
        end

        scope.on_body { |body| function.body = body }
      when "const"
        function = Program::Function.new(
          AST::Identifier.new("non").from(declare.terms.first),
          terms["name"].as(AST::Identifier),
          nil,
          terms["type"]?.as(AST::Term?),
        ).tap do |f|
          f.add_tag(:constant)
          f.add_tag(:inline)
        end

        scope.current_type.functions << function

        scope.on_body { |body| function.body = body }
      when "ffi"
        name, params =
          AST::Extract.name_and_params(terms["name_and_params"].not_nil!)

        scope.current_function = function = Program::Function.new(
          AST::Identifier.new("non").from(declare.terms.first),
          name,
          params,
          terms["ret"]?.as(AST::Term?),
        )

        function.add_tag(:ffi)
        function.add_tag(:inline)
        function.add_tag(:variadic) if terms["variadic"]?

        ffi_link_name = function.ident.value
        ffi_link_name = ffi_link_name[0...-1] if ffi_link_name.ends_with?("!")
        function.metadata[:ffi_link_name] = ffi_link_name

        function.body = nil
      when "let", "var"
        type = scope.current_type

        # TODO: Move this error to a later compiler pass?
        Error.at declare.terms.first, "stateless types can't have properties" \
          if type.has_tag?(:simple_value) || type.has_tag?(:ignores_cap)

        is_let = declarator.name.value == "let"

        # TODO: Move this error to a later compiler pass?
        Error.at declare.terms.first,
          "This type can't have any reassignable fields; use `let` here" \
          if !is_let && type.has_tag?(:no_field_reassign)

        keyword = declare.terms.first
        ident = terms["name"].as(AST::Identifier)
        ret = terms["type"]?.as(AST::Term?)

        field_cap = AST::Identifier.new("box").from(keyword)
        field_params = AST::Group.new("(").from(ident)
        field_func = Program::Function.new(field_cap, ident.dup, field_params, ret.dup)
        field_func.add_tag(:hygienic)
        field_func.add_tag(:field)
        field_func.add_tag(:let) if is_let
        type.functions << field_func

        scope.on_body { |body| field_func.body = body }

        getter_cap = AST::Identifier.new("box").from(keyword)
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
        type.functions << getter_func

        setter_cap = AST::Identifier.new("ref").from(keyword)
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
        type.functions << setter_func

        displace_cap = AST::Identifier.new("ref").from(keyword)
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
          displace_ret = ret.dup
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
        type.functions << displace_func
      when "is"
        scope.current_type.functions << Program::Function.new(
          AST::Identifier.new("non").from(declare.terms.first),
          declare.terms.first.as(AST::Identifier),
          nil,
          terms["trait"].as(AST::Term),
          nil,
        ).tap(&.add_tag(:hygienic)).tap(&.add_tag(:is)).tap(&.add_tag(:copies))
      when "copies"
        scope.current_type.functions << Program::Function.new(
          AST::Identifier.new("non").from(declare.terms.first),
          declare.terms.first.as(AST::Identifier),
          nil,
          terms["trait"].as(AST::Term),
          nil,
        ).tap(&.add_tag(:hygienic)).tap(&.add_tag(:copies))
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within a numeric type definition.
    when "type_numeric"
      case declarator.name.value
      when "signed"
        scope.current_type.add_tag(:numeric_signed)
        scope.current_type.functions << Program::Function.new(
          AST::Identifier.new("non").from(declare.terms.first),
          AST::Identifier.new("is_signed").from(declare.terms.first),
          nil,
          nil,
          AST::Group.new(":", [
            AST::Identifier.new("True").from(declare.terms.first).as(AST::Node)
          ]).from(declare.terms.first)
        ).tap do |f|
          f.add_tag(:constant)
          f.add_tag(:inline)
        end
      when "floating_point"
        scope.current_type.add_tag(:numeric_signed)
        scope.current_type.functions << Program::Function.new(
          AST::Identifier.new("non").from(declare.terms.first),
          AST::Identifier.new("is_signed").from(declare.terms.first),
          nil,
          nil,
          AST::Group.new(":", [
            AST::Identifier.new("True").from(declare.terms.first).as(AST::Node)
          ]).from(declare.terms.first)
        ).tap do |f|
          f.add_tag(:constant)
          f.add_tag(:inline)
        end

        scope.current_type.add_tag(:numeric_floating_point)
        scope.current_type.functions << Program::Function.new(
          AST::Identifier.new("non").from(declare.terms.first),
          AST::Identifier.new("is_floating_point").from(declare.terms.first),
          nil,
          nil,
          AST::Group.new(":", [
            AST::Identifier.new("True").from(declare.terms.first).as(AST::Node)
          ]).from(declare.terms.first)
        ).tap do |f|
          f.add_tag(:constant)
          f.add_tag(:inline)
        end
      when "bit_width"
        value_ast = terms["value"]?.as(AST::LiteralInteger?)
        c_type_ast = terms["c_type"]?.as(AST::Identifier?)
        if value_ast
          scope.current_type.metadata[:numeric_bit_width] = value_ast.value.to_u64
          scope.current_type.functions << Program::Function.new(
            AST::Identifier.new("non").from(declare.terms.first),
            AST::Identifier.new("bit_width").from(declare.terms.first),
            nil,
            AST::Identifier.new("U8").from(declare.terms.first),
            AST::Group.new(":", [value_ast.as(AST::Node)]).from(value_ast)
          ).tap do |f|
            f.add_tag(:constant)
            f.add_tag(:inline)
          end
        elsif c_type_ast
          scope.current_type.metadata[:numeric_bit_width] = 0
          scope.current_type.metadata[:numeric_bit_width_of_c_type] = true
          scope.current_type.functions << Program::Function.new(
            AST::Identifier.new("non").from(declare.terms.first),
            AST::Identifier.new("bit_width").from(declare.terms.first),
            nil,
            AST::Identifier.new("U8").from(declare.terms.first),
            AST::Group.new(":", [
              AST::Group.new(" ", [
                AST::Identifier.new("compiler").from(c_type_ast).as(AST::Node),
                AST::Identifier.new("intrinsic").from(c_type_ast).as(AST::Node),
              ]).from(c_type_ast).as(AST::Node)
            ]).from(c_type_ast)
          ).tap do |f|
            f.add_tag(:constant)
            f.add_tag(:inline)
          end
        else
          raise NotImplementedError.new(declarator.pretty_inspect)
        end
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within an enum type definition.
    when "type_enum"
      case declarator.name.value
      when "member"
        name = terms["name"].as(AST::Identifier)
        name.value = "#{scope.current_type.ident.value}.#{name.value}" \
          unless terms["noprefix"]?

        type_with_value = Program::TypeWithValue.new(
          name,
          scope.current_type.make_link(scope.current_package),
        )

        type_with_value.value =
          terms["value"].as(AST::LiteralInteger).value.to_u64

        scope.current_members << type_with_value # TODO: remove this line
        scope.current_package.enum_members << type_with_value
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within a function definition.
    when "function"
      case declarator.name.value
      when "inline"
        scope.current_function.add_tag(:inline)
      when "yields"
        scope.current_function.yield_out = terms["out"]?.as(AST::Term?)
        scope.current_function.yield_in  = terms["in"]?.as(AST::Term?)
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    else
      raise NotImplementedError.new(declarator.pretty_inspect)
    end
  end

  def self.finish(
    ctx : Compiler::Context,
    scope : Declarator::Scope,
    declarator : Declarator,
  )
    case declarator.name.value
    when "manifest"
      scope.current_package.manifests_declared << scope.current_manifest
      scope.current_manifest = nil
    when "manifest_dependency"
      scope.current_manifest_dependency = nil
    when "declarator"
      scope.current_package.declarators << scope.current_declarator
      scope.current_declarator = nil
    when "term"
      scope.current_declarator.terms << scope.current_declarator_term
      scope.current_declarator_term = nil
    when "fun", "be", "new", "ffi"
      scope.current_type.functions << scope.current_function
      scope.current_function = nil
    when "actor", "class", "struct", "module"
      scope.current_package.types << scope.current_type
      scope.current_type = nil
    when "numeric"
      scope.current_type.metadata[:numeric_bit_width] ||= 8
      declare_numeric_copies(ctx, scope, declarator)

      scope.current_package.types << scope.current_type
      scope.current_type = nil
    when "enum"
      scope.current_type.metadata[:numeric_bit_width] ||= 8
      declare_numeric_copies(ctx, scope, declarator)
      declare_enum_member_name(ctx, scope, declarator)
      declare_enum_from_u64(ctx, scope, declarator)

      scope.current_package.types << scope.current_type
      scope.current_type = nil
      scope.current_members = nil
    when "trait"
      # A trait's functions should have their body removed.
      scope.current_type.functions.each { |f|
        f.body = nil if f.body.try(&.terms).try(&.empty?)
      }

      scope.current_package.types << scope.current_type
      scope.current_type = nil
    when "ffimodule"
      # An FFI module's functions should be tagged as "ffi" and body removed.
      scope.current_type.functions.each { |f|
        f.add_tag(:ffi)
        f.add_tag(:inline)
        ffi_link_name = f.ident.value
        ffi_link_name = ffi_link_name[0...-1] if ffi_link_name.ends_with?("!")
        f.metadata[:ffi_link_name] = ffi_link_name
        f.body = nil
      }

      scope.current_package.types << scope.current_type
      scope.current_type = nil
    else
      nil
    end
  end

  def self.declare_numeric_copies(
    ctx : Compiler::Context,
    scope : Declarator::Scope,
    declarator : Declarator,
  )
    type = scope.current_type

    # Add "is Numeric(@)" to the type definition as well.
    trait_cap = AST::Identifier.new("non").from(type.ident)
    trait_is = AST::Identifier.new("is").from(type.ident)
    trait_ret = AST::Qualify.new(
      AST::Identifier.new("Numeric").from(type.ident),
      AST::Group.new("(", [
        AST::Identifier.new("@").from(type.ident)
      ] of AST::Node).from(type.ident)
    ).from(type.ident)
    trait_func = Program::Function.new(trait_cap, trait_is, nil, trait_ret, nil)
    trait_func.add_tag(:hygienic)
    trait_func.add_tag(:is)
    trait_func.add_tag(:copies)
    type.functions << trait_func

    # Add "copies Numeric.BaseImplementation" so to absorb the numeric base.
    copy_cap = AST::Identifier.new("non").from(type.ident)
    copy_is = AST::Identifier.new("copies").from(type.ident)
    copy_ret = AST::Identifier.new("Numeric.BaseImplementation").from(type.ident)
    copy_func = Program::Function.new(copy_cap, copy_is, nil, copy_ret, nil)
    copy_func.add_tag(:hygienic)
    copy_func.add_tag(:copies)
    type.functions << copy_func

    # Add "is" for the trait of this specific flavor of numeric.
    trait2_name =
      if type.has_tag?(:numeric_floating_point)
        "FloatingPoint"
      else
        "Integer"
      end
    trait2_cap = AST::Identifier.new("non").from(type.ident)
    trait2_is = AST::Identifier.new("is").from(type.ident)
    trait2_ret = AST::Qualify.new(
      AST::Identifier.new("Numeric").from(type.ident),
      AST::Group.new("(", [
        AST::Identifier.new("@").from(type.ident)
      ] of AST::Node).from(type.ident)
    ).from(type.ident)
    trait2_func = Program::Function.new(trait2_cap, trait2_is, nil, trait2_ret, nil)
    trait2_func.add_tag(:hygienic)
    trait2_func.add_tag(:is)
    trait2_func.add_tag(:copies)
    type.functions << trait2_func

    # Also copy the base implementation for this specific flavor of numeric.
    copy2_name =
      if !type.has_tag?(:numeric_floating_point)
        "Integer.BaseImplementation"
      elsif scope.current_type.metadata[:numeric_bit_width]? == 32
        "FloatingPoint.BaseImplementation32"
      else
        "FloatingPoint.BaseImplementation64"
      end
    copy2_cap = AST::Identifier.new("non").from(type.ident)
    copy2_is = AST::Identifier.new("copies").from(type.ident)
    copy2_ret = AST::Identifier.new(copy2_name).from(type.ident)
    copy2_func = Program::Function.new(copy2_cap, copy2_is, nil, copy2_ret, nil)
    copy2_func.add_tag(:hygienic)
    copy2_func.add_tag(:copies)
    type.functions << copy2_func
  end

  def self.declare_enum_member_name(
    ctx : Compiler::Context,
    scope : Declarator::Scope,
    declarator : Declarator,
  )
    type = scope.current_type

    # Each member gets a clause in the choice.
    member_name_choices = [] of {AST::Term, AST::Term}
    scope.current_members.each do |member|
      member_name_choices << {
        # Test if this value is equal to this member.
        AST::Relate.new(
          AST::Identifier.new("@").from(member.ident),
          AST::Operator.new("==").from(member.ident),
          AST::Identifier.new(member.ident.value).from(member.ident),
        ).from(type.ident),
        # If true, then the value is the string literal for that member.
        AST::LiteralString.new(member.ident.value).from(member.ident),
      }
    end
    # Otherwise, the member name is returned as an empty string. Sad.
    member_name_choices << {
      AST::Identifier.new("True").from(type.ident),
      AST::LiteralString.new("").from(type.ident),
    }

    # Create a function body containing that choice as its only expression.
    member_name_body = AST::Group.new(":").from(type.ident)
    member_name_body.terms <<
      AST::Choice.new(member_name_choices).from(type.ident)

    # Finally, create a function with that body.
    member_name_func = Program::Function.new(
      AST::Identifier.new("box").from(type.ident),
      AST::Identifier.new("member_name").from(type.ident),
      nil,
      AST::Identifier.new("String").from(type.ident),
      member_name_body,
    )
    scope.current_type.functions << member_name_func
  end

  # An enum type gets a method for converting from U64.
  def self.declare_enum_from_u64(
    ctx : Compiler::Context,
    scope : Declarator::Scope,
    declarator : Declarator,
  )
    type = scope.current_type

    # Each member gets a clause in the choice.
    from_u64_choices = [] of {AST::Term, AST::Term}
    scope.current_members.each do |member|
      from_u64_choices << {
        # Test if this value is equal to this member.
        AST::Relate.new(
          AST::Relate.new(
            AST::Identifier.new(member.ident.value).from(member.ident),
            AST::Operator.new(".").from(member.ident),
            AST::Identifier.new("u64").from(member.ident),
          ).from(type.ident),
          AST::Operator.new("==").from(member.ident),
          AST::Identifier.new("value").from(member.ident),
        ).from(type.ident),
        # If true, then the member is returned.
        AST::Identifier.new(member.ident.value).from(member.ident),
      }
    end
    # Otherwise, an error is raised. Sad.
    from_u64_choices << {
      AST::Identifier.new("True").from(type.ident),
      AST::Jump.new(AST::Identifier.new("None").from(type.ident),
        AST::Jump::Kind::Error).from(type.ident),
    }

    # Create function parameters for the value parameter.
    from_u64_params = AST::Group.new("(").from(type.ident)
    from_u64_params.terms <<
      AST::Identifier.new("value").from(type.ident)

    # Create a function body containing that choice as its only expression.
    from_u64_body = AST::Group.new(":").from(type.ident)
    from_u64_body.terms <<
      AST::Choice.new(from_u64_choices).from(type.ident)

    # Finally, create a function with that body.
    from_u64_func = Program::Function.new(
      AST::Identifier.new("non").from(type.ident),
      AST::Identifier.new("from_u64!").from(type.ident),
      from_u64_params,
      AST::Identifier.new(type.ident.value).from(type.ident),
      from_u64_body,
    )
    type.functions << from_u64_func
  end
end
