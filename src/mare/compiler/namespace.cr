##
# The purpose of the Namespace pass is to determine which type names are visible
# from which source files, and to raise an appropriate error in the event that
# two types visible from the same source file have the same identifier.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the program level.
# This pass produces output state at the source and source library level.
#
class Mare::Compiler::Namespace
  @root_library : Source::Library?

  def initialize
    @types_by_library = Hash(Source::Library, Hash(String, Program::Type | Program::TypeAlias)).new
    @types_by_source = Hash(Source, Hash(String, Program::Type | Program::TypeAlias)).new
  end

  def run(ctx)
    # TODO: map by Program::Library instead of Source::Library
    @root_library = ctx.program.libraries.first.source_library

    ctx.program.types.each do |t|
      add_type_to_library(t)
      add_type_to_source(t)
    end
    ctx.program.aliases.each do |t|
      add_type_to_library(t)
      add_type_to_source(t)
    end

    @types_by_source.each do |source, source_types|
      add_prelude_types_to_source(source, source_types)
    end

    @types_by_source.each do |source, source_types|
      source_types.merge!(@types_by_library[source.library])
    end

    ctx.program.imports.each do |import|
      add_imported_types_to_source(import)
    end
  end

  # TODO: Can this be less hacky? It feels wrong to alter this state later.
  def add_lambda_type_later(new_type)
    add_type_to_library(new_type)
    add_type_to_source(new_type)
  end

  def [](x)
    result = self[x]?

    raise "failed to find asserted type in namespace: #{x.inspect}" \
      unless result

    result.not_nil!
  end

  # When given an Identifier, try to find the type starting from its source.
  # This is the way to resolve a type identifier in context.
  def []?(ident : AST::Identifier) : (Program::Type | Program::TypeAlias)?
    @types_by_source[ident.pos.source][ident.value]?
  end

  # When given a String name, try to find the type in the root or prelude.
  # This is a way to resolve a basic type when you don't have context.
  def []?(name : String) : (Program::Type | Program::TypeAlias)?
    @types_by_library[@root_library.not_nil!]?.try(&.[]?(name)) ||
    @types_by_library[Compiler.prelude_library]?.try(&.[]?(name))
  end

  # TODO: Remove this method?
  # This is only for use in testing.
  def find_func!(type_name, func_name)
    self[type_name].as(Program::Type).find_func!(func_name)
  end

  private def add_type_to_library(new_type)
    library = new_type.ident.pos.source.library
    name = new_type.ident.value

    types = @types_by_library[library] ||=
      Hash(String, Program::Type | Program::TypeAlias).new

    already_type = types[name]?
    if already_type
      Error.at new_type.ident.pos,
        "This type conflicts with another declared type in the same library", [
          {already_type.ident.pos, "the other type with the same name is here"}
        ]
    end

    types[name] = new_type
  end

  private def add_type_to_source(new_type)
    source = new_type.ident.pos.source
    name = new_type.ident.value

    types = @types_by_source[source] ||=
      Hash(String, Program::Type | Program::TypeAlias).new

    raise "should have been prevented by add_type_to_library" if types[name]?

    types[name] = new_type
  end

  private def add_prelude_types_to_source(source, source_types)
    # Skip adding prelude types to source files in the prelude library.
    return if source.library == Compiler.prelude_library

    @types_by_library[Compiler.prelude_library].each do |name, new_type|
      next if new_type.has_tag?(:private)

      already_type = source_types[name]?
      if already_type
        Error.at already_type.ident.pos,
          "This type's name conflicts with a mandatory built-in type", [
            {new_type.ident.pos, "the built-in type is defined here"},
          ]
      end

      source_types[name] = new_type
    end
  end

  private def add_imported_types_to_source(import)
    source = import.ident.pos.source
    library = import.resolved.source_library
    importable_types = @types_by_library[library]

    # Determine the list of types to be imported.
    imported_types = [] of Tuple(Source::Pos, Program::Type | Program::TypeAlias)
    if import.names
      import.names.not_nil!.terms.map do |ident|
        raise NotImplementedError.new(ident) unless ident.is_a?(AST::Identifier)

        new_type = importable_types[ident.value]?
        Error.at ident, "This type doesn't exist within the imported library" \
          unless new_type

        Error.at ident, "This type is private and cannot be imported" \
          if new_type.has_tag?(:private)

        imported_types << {ident.pos, new_type}
      end
    else
      importable_types.values.each do |new_type|
        next if new_type.has_tag?(:private)

        imported_types << {import.ident.pos, new_type}
      end
    end

    types = @types_by_source[source] ||=
      Hash(String, Program::Type | Program::TypeAlias).new

    # Import those types into the source, raising an error upon any conflict.
    imported_types.each do |import_pos, new_type|
      already_type = types[new_type.ident.value]?
      if already_type
        Error.at import_pos,
          "A type imported here conflicts with another " \
          "type already in this source file", [
            {new_type.ident.pos, "the imported type is here"},
            {already_type.ident.pos, "the other type with the same name is here"},
          ]
      end

      types[new_type.ident.value] = new_type
    end
  end
end
