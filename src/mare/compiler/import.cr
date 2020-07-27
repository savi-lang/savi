##
# The purpose of the Import pass is to load more library sources into memory,
# based on import directives found in the source files loaded so far.
# We continue loading source libraries until all imports have been resolved.
#
# This pass does not mutate the Program topology directly, though it instructs Context to compile more libraries.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the program level.
# This pass produces output state at the library import level.
#
class Mare::Compiler::Import
  def initialize
    @libraries_by_import = Hash(Program::Import, Program::Library::Link).new
  end

  def [](import : Program::Import) : Program::Library::Link
    @libraries_by_import[import]
  end

  # TODO: Refactor this method away, since compiler already runs at the library level.
  def run(ctx)
    # Copy the current list of libraries as our initial list, so that we
    # don't end up trying to iterate over a list that's being mutated.
    initial_libraries_list = ctx.program.libraries.dup

    # For each library in the program, run the Import pass on it.
    initial_libraries_list.each do |library|
      run_for_library(ctx, library)
    end
  end

  def run_for_library(ctx, library)
    # For each import statement found in the library, resolve it.
    library.imports.each.with_index do |import, i|
      # Skip imports that have already been resolved.
      next if @libraries_by_import.has_key?(import)

      # Assert that the imported relative path is a string.
      # TODO: remove this? why even allow a non-string here in the topology?
      relative_path = import.ident
      raise NotImplementedError.new(import.ident.to_a) \
        unless relative_path.is_a?(AST::LiteralString)

      # Check if we are linking library
      if (path = relative_path.value).starts_with? "lib:"
        path = path[4..path.size]
        ctx.link_libraries << path
        library.imports.delete_at(i)
        next
      end

      # Based on the source file that the import statement was declared in
      # and the relative path mentioned in the import statement itself,
      # get the absolute path for the library that is to be loaded.
      source = relative_path.pos.source
      path = Compiler.resolve_library_dirname(
        relative_path.value,
        source.library.path
      )

      # Finally, load the library, then recursively run this pass on it.
      loaded_library = load_library(ctx, path)
      @libraries_by_import[import] = loaded_library.make_link

      # Recursively run this pass on the loaded library.
      # TODO: In the future, rely on the compiler to run at the library level.
      run_for_library(ctx, loaded_library)
    end
  end

  def load_library(ctx, path) : Program::Library
    # First, try to find an already loaded library that has this same path.
    library = ctx.program.libraries.find(&.source_library.path.==(path))
    return library if library

    # Otherwise, use the Compiler to load the library now.
    library_sources = Compiler.get_library_sources(path)
    library_docs = library_sources.map { |s| Parser.parse(s) }
    ctx.compile_library(library_sources.first.library, library_docs)
  end
end
