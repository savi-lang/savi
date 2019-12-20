##
# The purpose of the Import pass is to load more library sources into memory,
# based on import directives found in the source files loaded so far.
# We continue loading source libraries until all imports have been resolved.
#
# This pass mutates the Program topology by assigning the Import#library fields.
# This pass reads ASTs (Import heads only) but does not mutate any ASTs.
# This pass may raise a compilation error.
# This pass keeps temporary state (on the stack) at the program level.
# This pass produces no output state.
#
module Mare::Compiler::Import
  def self.run(ctx)
    libraries = {} of String => Program::Library

    while true
      remaining = remaining_imports(ctx, libraries)
      break if remaining.empty?

      load_more_libraries(ctx, libraries, remaining)
    end
  end

  def self.remaining_imports(ctx, libraries)
    remaining = Array(Tuple(String, Program::Import)).new

    ctx.program.imports.each do |import|
      import_ident = import.ident
      raise NotImplementedError.new(import.ident.to_a) \
        unless import_ident.is_a?(AST::LiteralString)

      source = import_ident.pos.source
      path = Compiler.resolve_library_dirname(
        import_ident.value,
        source.library.path
      )

      library = libraries[path]?
      if library
        import.resolved = library
      else
        remaining << {path, import}
      end
    end

    remaining
  end

  def self.load_more_libraries(ctx, libraries, remaining)
    remaining.each do |path, import|
      library = libraries[path]?
      if library
        import.resolved = library
      else
        library = Program::Library.new

        docs =
          Compiler
          .get_library_sources(path)
          .map { |s| Parser.parse(s) }
          .tap(&.each { |doc| ctx.compile(library, doc) })

        library.source_library = docs.first.source.library

        libraries[path] = library
      end
    end
  end
end
