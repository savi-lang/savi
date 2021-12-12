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

        scope.current_manifest = manifest = Packaging::Manifest.new(name, kind)

        # Every manifest automatically "provides" its main name.
        manifest.provides_names << name
      when "import"
        scope.current_package.imports << Import.new(
          terms["path"].as(AST::LiteralString),
          terms["names"]?.as(AST::Group?),
        )
        # TODO: Also pull in the package's declarators in some way.
      when "source"
        scope.current_package.imports << Program::Import.new(
          terms["path"].as(AST::LiteralString),
          copy_sources: true
        )
        # TODO: Also pull in the package's declarators in some way.
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
           "numeric", "enum", "module", "ffi"
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
        when "ffi"
          type.add_tag(:singleton)
          type.add_tag(:ignores_cap)
          type.add_tag(:private)
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
        scope.current_manifest.sources_paths << path
      when "dependency"
        name = terms["name"].as(AST::Identifier)
        version = terms["version"].as(AST::LiteralString)
        scope.current_manifest_dependency = dep =
          Packaging::Dependency.new(name, version)
        scope.current_manifest.dependencies << dep
      when "transitive"
        name = terms["name"].as(AST::Identifier)
        version = terms["version"].as(AST::LiteralString)
        scope.current_manifest_dependency = dep =
          Packaging::Dependency.new(name, version, transitive: true)
        scope.current_manifest.dependencies << dep
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within a manifest dependency definition.
    when "manifest_dependency"
      case declarator.name.value
      when "from"
        location = terms["location"].as(AST::Identifier)
        scope.current_manifest_dependency.location_nodes << location
      when "lock"
        revision = terms["revision"].as(AST::Identifier)
        scope.current_manifest_dependency.revision_nodes << revision
      when "depends"
        name = terms["name"].as(AST::Identifier)
        scope.current_manifest_dependency.depends_on_nodes << name
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within a type definition.
    when "type", "type_singleton"
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
        ).tap(&.add_tag(:constant))

        scope.current_type.functions << function

        scope.on_body { |body| function.body = body }
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

    # Declarations within a enum type definition.
    when "type_enum"
      case declarator.name.value
      when "member"
        type_with_value = Program::TypeWithValue.new(
          terms["name"].as(AST::Identifier),
          scope.current_type.make_link(scope.current_package),
        )

        scope.on_body { |body|
          term = body.terms[0]?
          term = nil unless body.terms.size == 1

          # TODO: Figure out why Crystal needs the `as` coercions here.
          # I would have thought they'd be handled by the `is_a?` above them.
          if term.is_a?(AST::LiteralInteger)
            type_with_value.value = term.as(AST::LiteralInteger).value.to_u64
          elsif term.is_a?(AST::LiteralCharacter)
            type_with_value.value = term.as(AST::LiteralCharacter).value.to_u64
          else
            ctx.error_at body, "This member value must be a single integer"
          end
        }

        scope.current_members << type_with_value # TODO: remove this line
        scope.current_package.enum_members << type_with_value
      else
        raise NotImplementedError.new(declarator.pretty_inspect)
      end

    # Declarations within a function definition.
    when "function"
      case declarator.name.value
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
      ctx.program.manifests << scope.current_manifest
      scope.current_manifest = nil
    when "manifest_dependency"
      scope.current_manifest_dependency = nil
    when "declarator"
      scope.current_package.declarators << scope.current_declarator
      scope.current_declarator = nil
    when "term"
      scope.current_declarator.terms << scope.current_declarator_term
      scope.current_declarator_term = nil
    when "fun", "be", "new"
      scope.current_type.functions << scope.current_function
      scope.current_function = nil
    when "actor", "class", "struct", "module"
      scope.current_package.types << scope.current_type
      scope.current_type = nil
    when "numeric"
      declare_numeric_copies(ctx, scope, declarator)

      scope.current_package.types << scope.current_type
      scope.current_type = nil
    when "enum"
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
    when "ffi"
      # An FFI type's functions should be tagged as "ffi" and body removed.
      scope.current_type.functions.each { |f|
        f.add_tag(:ffi)
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

    # Add "is Numeric" to the type definition so to absorb the trait.
    trait_cap = AST::Identifier.new("non").from(type.ident)
    trait_is = AST::Identifier.new("is").from(type.ident)
    trait_ret = AST::Identifier.new("Numeric").from(type.ident)
    trait_func = Program::Function.new(trait_cap, trait_is, nil, trait_ret, nil)
    trait_func.add_tag(:hygienic)
    trait_func.add_tag(:is)
    trait_func.add_tag(:copies)
    type.functions << trait_func

    # Add "copies NumericMethods" to the type definition as well.
    copy_cap = AST::Identifier.new("non").from(type.ident)
    copy_is = AST::Identifier.new("copies").from(type.ident)
    copy_ret = AST::Identifier.new("NumericMethods").from(type.ident)
    copy_func = Program::Function.new(copy_cap, copy_is, nil, copy_ret, nil)
    copy_func.add_tag(:hygienic)
    copy_func.add_tag(:copies)
    type.functions << copy_func

    # Also copy IntegerMethods, Float32Methods, or Float64Methods.
    spec_name =
      if !type.const_bool_true?("is_floating_point")
        "IntegerMethods"
      elsif type.const_u64_eq?("bit_width", 32)
        "Float32Methods"
      else
        "Float64Methods"
      end
    spec_cap = AST::Identifier.new("non").from(type.ident)
    spec_is = AST::Identifier.new("copies").from(type.ident)
    spec_ret = AST::Identifier.new(spec_name).from(type.ident)
    spec_func = Program::Function.new(spec_cap, spec_is, nil, spec_ret, nil)
    spec_func.add_tag(:hygienic)
    spec_func.add_tag(:copies)
    type.functions << spec_func
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
