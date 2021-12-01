##
# The purpose of the PopulateTypes pass is to create missing types,
# such as types implied by namespace-nested types whose outer type
# does not yet exist in the library.
#
# This pass uses copy-on-mutate patterns to "mutate" the Program topology.
# This pass does not mutate ASTs, but creates new types.
# This pass may raise a compilation error.
# This pass keeps temporary state (on the stack) at the per-type level.
# This pass produces no output state.
#
class Savi::Compiler::PopulateTypes
  def initialize
  end

  def run(ctx, library)
    # If this library has any types whose identifier is nested under a type that
    # does not actually exist yet, create a module to act as the namespace type.
    missing_namespace_modules = [] of AST::Identifier
    library.types.each { |t|
      maybe_note_missing_namespace_module_for(ctx, t.ident, library, missing_namespace_modules)
    }
    library.enum_members.each { |t|
      maybe_note_missing_namespace_module_for(ctx, t.ident, library, missing_namespace_modules)
    }
    new_namespace_modules = missing_namespace_modules.map { |ident|
      Program::Type.new(
        AST::Identifier.new("non").from(ident),
        ident,
      ).tap { |new_t|
        new_t.add_tag(:singleton)
        new_t.add_tag(:ignores_cap)
      }
    }

    return library if new_namespace_modules.empty?

    orig_types = library.types
    library = library.dup
    raise "didn't dup types!" if library.types.same?(orig_types)
    library.types.concat(new_namespace_modules)

    library
  end

  def maybe_note_missing_namespace_module_for(ctx, ident, library, missing_namespace_modules)
    # If it's not a nested identifier at all, stop here.
    return unless ident.value.includes?(".")

    # If it's already accounted for as an existing type, stop here.
    return if library.types.any? { |outer|
      ident.immediately_nested_within?(outer.ident)
    }
    return if library.enum_members.any? { |outer|
      ident.immediately_nested_within?(outer.ident)
    }

    # If it's already in the list of missing namespace modules, stop here.
    new_ident = AST::Identifier.new(ident.value.sub(/\.\w+\z/, "")).from(ident)
    return if missing_namespace_modules.any?(&.value.==(new_ident.value))

    # Otherwise, add it to the list.
    missing_namespace_modules << new_ident

    # And also recurse in case we need to also create additional nest levels.
    maybe_note_missing_namespace_module_for(ctx, new_ident, library, missing_namespace_modules)
  end
end
