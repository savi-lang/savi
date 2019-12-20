##
# The purpose of the Import pass is to load more library sources into memory,
# based on import directives found in the source files loaded so far.
# We continue loading source libraries until all imports have been resolved.
#
# This pass mutates the Program topology by assigning the Import#resolved field.
# This pass reads ASTs (Import heads only) but does not mutate any ASTs.
# This pass may raise a compilation error.
# This pass keeps no state (other than the Program topology itself).
# This pass produces no output state.
#
module Mare::Compiler::Import
  def self.run(ctx)
    # Copy the current list of libraries as our initial list, so that we
    # don't end up trying to iterate over a list that's being mutated.
    initial_libraries_list = ctx.program.libraries.dup

    # For each library in the program, run the Import pass on it.
    # TODO: In the future, rely on the compiler to run at the library level.
    initial_libraries_list.each do |library|
      run_for_library(ctx, library)
    end
  end

  def self.run_for_library(ctx, library)
    # For each import statement found in the library, resolve it.
    library.imports.each do |import|
      # Skip imports that have already been resolved.
      next if import.resolved?

      # Assert that the imported relative path is a string.
      # TODO: remove this? why even allow a non-string here in the topology?
      relative_path = import.ident
      raise NotImplementedError.new(import.ident.to_a) \
        unless relative_path.is_a?(AST::LiteralString)

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
      import.resolved = loaded_library

      # Recursively run this pass on the loaded library.
      # TODO: In the future, rely on the compiler to run at the library level.
      run_for_library(ctx, loaded_library)
    end
  end

  def self.load_library(ctx, path) : Program::Library
    # First, try to find an already loaded library that has this same path.
    library = ctx.program.libraries.find(&.source_library.path.==(path))
    return library if library

    # Otherwise, use the Compiler to load the library now.
    library = Program::Library.new
    docs =
      Compiler
        .get_library_sources(path)
        .map { |s| Parser.parse(s) }
        .tap(&.each { |doc| ctx.compile(library, doc) })
    library.source_library = docs.first.source.library
    library
  end
end
