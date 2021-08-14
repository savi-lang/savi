class Savi::Compiler::SourceService
  property standard_library_dirname =
    File.expand_path("../../../packages", __DIR__)

  def initialize
  end

  def resolve_library_dirname(libname, from_dirname = nil)
    standard_dirname = File.expand_path(libname, standard_library_dirname)
    relative_dirname = File.expand_path(libname, from_dirname) if from_dirname

    if relative_dirname && Dir.exists?(relative_dirname)
      relative_dirname
    elsif Dir.exists?(standard_dirname)
      standard_dirname
    else
      raise "Couldn't find a library directory named #{libname.inspect}" \
        "#{" (relative to #{from_dirname.inspect})" if from_dirname}"
    end
  end

  def get_library_sources(dirname, library : Source::Library? = nil)
    library ||= Source::Library.new(dirname)

    sources = Dir.entries(dirname).compact_map { |name|
      next unless name.ends_with?(".savi")
      language = :savi

      content = File.read(File.join(dirname, name))
      Source.new(dirname, name, content, library, language)
    } rescue [] of Source

    Error.at Source::Pos.show_library_path(library),
      "No '.savi' source files found in this directory" \
        if sources.empty?

    sources
  end

  def get_recursive_sources(root_dirname, language = :savi)
    sources = Dir.glob("#{root_dirname}/**/*.#{language.to_s}").map { |path|
      name = File.basename(path)
      dirname = File.dirname(path)
      library = Source::Library.new(dirname)
      content = File.read(File.join(dirname, name))
      Source.new(dirname, name, content, library, language)
    } rescue [] of Source

    Error.at Source::Pos.show_library_path(Source::Library.new(root_dirname)),
      "No '.#{language.to_s}' source files found recursively within this root" \
        if sources.empty?

    sources
  end
end
