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
class Savi::Compiler::Namespace
  struct SourceAnalysis
    protected getter types

    def initialize(@source : Source)
      @types = {} of String => (
        Program::Type::Link | Program::TypeAlias::Link | Program::TypeWithValue::Link \
      )
    end

    def [](name : String); @types[name]; end
    def []?(name : String); @types[name]?; end
  end

  def initialize
    @types_by_library = Hash(Program::Library::Link, Hash(String,
      Program::Type::Link | Program::TypeAlias::Link | Program::TypeWithValue::Link
    )).new
    @source_analyses = Hash(Source, SourceAnalysis).new
  end

  def main_type!(ctx); main_type?(ctx).not_nil! end
  def main_type?(ctx): Program::Type::Link?
    @types_by_library[ctx.root_library_link]["Main"]?.as(Program::Type::Link?)
  end

  def run(ctx)
    # Take note of the library and source file in which each type occurs.
    ctx.program.libraries.each do |library|
      library.types.each do |t|
        check_conflicting_functions(ctx, t, t.make_link(library))
        add_type_to_library(ctx, t, library)
        add_type_to_source(t, library)
      end
      library.aliases.each do |t|
        add_type_to_library(ctx, t, library)
        add_type_to_source(t, library)
      end
      library.enum_members.each do |t|
        add_type_to_library(ctx, t, library)
        add_type_to_source(t, library)
      end
    end

    # Every source file implicitly has access to all prelude types.
    @source_analyses.each do |source, source_analysis|
      add_prelude_types_to_source(ctx, source, source_analysis)
    end

    # Every source file implicitly has access to all types in the same library.
    ctx.program.libraries.each do |library|
      @source_analyses.each do |source, source_analysis|
        next unless source.library == library.source_library
        source_analysis.types.merge!(@types_by_library[library.make_link])
      end
    end

    # Every source file has access to all explicitly imported types.
    ctx.program.libraries.flat_map(&.imports).each do |import|
      add_imported_types_to_source(ctx, import)
    end
  end

  # TODO: Can this be less hacky? It feels wrong to alter this state later.
  def add_lambda_type_later(ctx : Context, new_type : Program::Type, library : Program::Library)
    check_conflicting_functions(ctx, new_type, new_type.make_link(library))
    add_type_to_library(ctx, new_type, library)
    add_type_to_source(new_type, library)
  end

  # When given a Source, return the set of analysis for that source.
  # TODO: Get rid of other forms of [] here in favor of this one.
  def [](source : Source) : SourceAnalysis
    @source_analyses[source]
  end

  def prelude_library_link(ctx)
    Program::Library::Link.new(ctx.compiler.source_service.prelude_library_path)
  end

  # When given a String name, try to find the type in the prelude library.
  # This is a way to resolve a builtin type by name without more context.
  def prelude_type(ctx, name : String) : Program::Type::Link
    @types_by_library[prelude_library_link(ctx)][name].as(Program::Type::Link)
  end

  # TODO: Remove this method?
  # This is only for use in testing.
  def find_func!(ctx, source, type_name, func_name)
    self[source][type_name].as(Program::Type::Link).resolve(ctx).find_func!(func_name)
  end

  private def check_conflicting_functions(ctx, t, t_link : Program::Type::Link)
    # Find any functions that would resolve to the same link - not allowed.
    t.functions.group_by(&.make_link(t_link)).each do |f_link, fs|
      next if fs.size <= 1

      f_first = fs.shift
      Error.at f_first.ident.pos,
        "This name conflicts with others declared in the same type",
        fs.map { |f| {f.ident.pos, "a conflicting declaration is here"} }
    end
  end

  private def add_type_to_library(ctx, new_type, library)
    name = new_type.ident.value

    types = @types_by_library[library.make_link] ||= Hash(String,
      Program::Type::Link | Program::TypeAlias::Link | Program::TypeWithValue::Link
    ).new

    already_type_link = types[name]?
    if already_type_link
      already_type = already_type_link.resolve(ctx)
      Error.at new_type.ident.pos,
        "This type conflicts with another declared type in the same library", [
          {already_type.ident.pos, "the other type with the same name is here"}
        ]
    end

    types[name] = new_type.make_link(library)
  end

  private def add_type_to_source(new_type, library)
    source = new_type.ident.pos.source
    name = new_type.ident.value

    source_analysis = @source_analyses[source] ||= SourceAnalysis.new(source)

    raise "should have been prevented by add_type_to_library" \
      if source_analysis.types[name]?

    source_analysis.types[name] = new_type.make_link(library)
  end

  private def add_prelude_types_to_source(ctx, source, source_analysis)
    # Skip adding prelude types to source files in the prelude library.
    return if source.library.path == ctx.compiler.source_service.prelude_library_path

    @types_by_library[prelude_library_link(ctx)].each do |name, new_type_link|
      new_type = new_type_link.resolve(ctx)
      next if new_type.has_tag?(:private)

      already_type = source_analysis.types[name]?.try(&.resolve(ctx))
      if already_type
        Error.at already_type.ident.pos,
          "This type's name conflicts with a mandatory built-in type", [
            {new_type.ident.pos, "the built-in type is defined here"},
          ]
      end

      source_analysis.types[name] = new_type_link
    end
  end

  private def add_imported_types_to_source(ctx, import)
    source = import.ident.pos.source
    importable_types = @types_by_library[ctx.import[import]]

    # Determine the list of types to be imported.
    imported_types = [] of Tuple(Source::Pos,
      Program::Type::Link | Program::TypeAlias::Link | Program::TypeWithValue::Link
    )
    if import.names
      import.names.not_nil!.terms.map do |ident|
        raise NotImplementedError.new(ident) unless ident.is_a?(AST::Identifier)

        new_type_link = importable_types[ident.value]?
        Error.at ident, "This type doesn't exist within the imported library" \
          unless new_type_link

        new_type = new_type_link.resolve(ctx)
        Error.at ident, "This type is private and cannot be imported" \
          if new_type.has_tag?(:private)

        imported_types << {ident.pos, new_type_link}
      end
    else
      importable_types.values.each do |new_type_link|
        new_type = new_type_link.resolve(ctx)
        next if new_type.has_tag?(:private)

        imported_types << {import.ident.pos, new_type_link}
      end
    end

    source_analysis = @source_analyses[source] ||= SourceAnalysis.new(source)

    # Import those types into the source, raising an error upon any conflict.
    imported_types.each do |import_pos, new_type_link|
      new_type = new_type_link.resolve(ctx)

      already_type_link = source_analysis.types[new_type.ident.value]?
      if already_type_link
        already_type = already_type_link.resolve(ctx)
        Error.at import_pos,
          "A type imported here conflicts with another " \
          "type already in this source file", [
            {new_type.ident.pos, "the imported type is here"},
            {already_type.ident.pos, "the other type with the same name is here"},
          ]
      end

      source_analysis.types[new_type.ident.value] = new_type_link
    end
  end
end
