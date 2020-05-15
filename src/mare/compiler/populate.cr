##
# The purpose of the Populate pass is to copy a set of functions from one type
# to another, such that any functions missing in the destination type will be
# copied from the source type. In the most common case, this is caused by
# an "is" annotation on a type denoting an inheritance relationship.
# The Populate pass also creates missing methods, like the default constructor.
#
# This pass uses copy-on-mutate patterns to "mutate" the Program topology.
# This pass does not mutate ASTs, but copies whole functions to other types.
# This pass may raise a compilation error.
# This pass keeps temporary state (on the stack) at the per-type level.
# This pass produces no output state.
#
module Mare::Compiler::Populate
  def self.run(ctx, library)
    library.types_map_cow do |dest|
      orig_functions = dest.functions
      dest_link = dest.make_link(library)

      # Copy functions into the type from other sources.
      orig_functions.each do |f|
        # Only look at functions that have the "copies" tag.
        # Often these "functions" are actually "is" annotations.
        next unless f.has_tag?(:copies)

        dest_copies_link = f.make_link(dest_link)

        # Find the type associated with the "return value" of the "function"
        # and copy the functions from it that we need.
        ret = f.ret
        case ret
        when AST::Identifier
          source = ctx.refer_type[dest_copies_link][ret]?
          Error.at ret, "This type couldn't be resolved" unless source
          source = source.as(Refer::Type) # TODO: handle cases of Refer::TypeAlias or Refer::TypeParam
          source_defn = source.defn(ctx)
        when AST::Qualify
          source = ctx.refer_type[dest_copies_link][ret.term.as(AST::Identifier)]?
          Error.at ret, "This type couldn't be resolved" unless source
          source = source.as(Refer::Type) # TODO: handle cases of Refer::TypeAlias or Refer::TypeParam

          # We need to build an intercessor redirect mapping the refer_type
          # analysis that will take place on the new functions that will be
          # copied from the source type to the dest type. This is necessary
          # because the source type may contain references to type parameters
          # that were supplied by type arguments within the dest type's source.
          # So we build a mapping that will replace instances of the type param.
          new_refer_type_analysis = ReferTypeAnalysis.new(ctx.refer_type[source.link])
          source_defn = source.defn(ctx)
          source_defn_params_size = source_defn.params.try(&.terms.size) || 0
          [source_defn_params_size, ret.group.terms.size].min.times do |index|
            # Get the Refer info of the type parameter identifier.
            type_param_ast = source_defn.params.not_nil!.terms[index]
            type_param_ident = AST::Extract.type_param(type_param_ast)[0]
            type_param_ref = ctx.refer_type[source.link][type_param_ident]

            # Get the Refer info of the type argument's type name identifier.
            replacement_ast = ret.group.terms[index]
            replacement_ident = AST::Extract.type_arg(replacement_ast)[0]
            replacement_ref = ctx.refer_type[dest_copies_link][replacement_ident]

            # Introduce the mapping for this redirect into the analysis struct
            # that we will use as an intercessor.
            new_refer_type_analysis.redirect(type_param_ref, replacement_ref)
          end
        else
          raise NotImplementedError.new(ret)
        end

        new_functions = copy_from(ctx, source_defn, dest)
        if new_functions.any?
          if dest.functions.same?(orig_functions)
            dest = dest.dup
            raise "didn't dup functions!" if dest.functions.same?(orig_functions)
          end
          dest.functions.concat(new_functions)
        end

        # Run the missing refer_type pass on the new functions on the dest type.
        # Use the special intercessor redirect mapping we created earlier,
        # in the case that type params were used; otherwise it will be nil.
        new_functions.each do |f|
          ctx.refer_type.run_for_func(
            ctx,
            f,
            f.make_link(dest_link),
            new_refer_type_analysis,
          )
        end
      end

      # If the type doesn't have a constructor and needs one, then add one.
      if dest.has_tag?(:allocated) && !dest.has_tag?(:abstract) \
      && !dest.functions.any? { |f| f.has_tag?(:constructor) }
        func = Program::Function.new(
          AST::Identifier.new("ref").from(dest.ident),
          AST::Identifier.new("new").from(dest.ident),
          nil,
          nil,
          AST::Group.new(":").from(dest.ident).tap { |body|
            body.terms << AST::Identifier.new("@").from(dest.ident)
          },
        ).tap do |f|
          f.add_tag(:constructor)
          f.add_tag(:async) if dest.has_tag?(:actor)
        end

        if dest.functions.same?(orig_functions)
          dest = dest.dup
          raise "didn't dup functions!" if dest.functions.same?(orig_functions)
        end
        dest.functions << func
      end

      dest
    end
  end

  # For each concrete function in the given source, copy it to the destination
  # if the destination doesn't already have an implementation for it.
  # Don't actually copy yet - just return the new functions to be copied in.
  def self.copy_from(
    ctx : Context,
    source : Program::Type,
    dest : Program::Type
  )
    new_functions = [] of Program::Function

    source.functions.each do |f|
      if !f.has_tag?(:field) # always copy fields; skip these checks if a field
        # We ignore hygienic functions entirely.
        next if f.has_tag?(:hygienic)

        # We don't copy functions that have no implementation.
        next if f.body.nil? && !f.has_tag?(:compiler_intrinsic)

        # We won't copy a function if the dest already has one of the same name.
        next if dest.find_func?(f.ident.value)
      end

      # Add the function to the list of those that we will add to the dest type.
      new_functions << f
    end

    new_functions
  end
end
