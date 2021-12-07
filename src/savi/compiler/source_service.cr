class Savi::Compiler::SourceService
  property standard_library_internal_path =
    File.expand_path("../../packages", Process.executable_path.not_nil!)

  property standard_directory_remap : {String, String}?
  property main_directory_remap : {String, String}?

  def initialize
    @source_overrides = {} of String => Hash(String, String)
  end

  def standard_library_path
    from_internal_path(standard_library_internal_path)
  end
  def core_savi_library_path
    File.join("#{standard_library_path}/Savi")
  end
  def standard_declarators_library_path
    File.join("#{standard_library_path}/Savi/declarators")
  end
  def meta_declarators_library_path
    File.join("#{standard_library_path}/Savi/declarators/meta")
  end

  # Add/update a source override, which causes the SourceService to pretend as
  # if there is a file at the given path with the given content in it.
  #
  # If there really is a file at that path, the source override will shadow it,
  # overriding the real content of the file for as long as the override exists.
  # If there is no such file at that path, the source override makes the system
  # pretend as if there is a file there, so it will show up in that directory
  # if and when the directory is compiled as a library in the program.
  #
  # This is used by editor-interactive systems like the language server,
  # allowing the content in the text editor that has opened the given file
  # to temporarily override whatever content is actually saved to disk there.
  # This allows us to compile as the user is typing, even if they haven't saved.
  def set_source_override(path, content)
    dirname = File.dirname(path)
    name = File.basename(path)
    (@source_overrides[dirname] ||= {} of String => String)[name] = content
  end

  # Remove the source override at the given path, if it exists.
  #
  # This corresponds to the closing of a file in a text editor.
  #
  # See docs for `set_source_override` for more information.
  def unset_source_override(path)
    dirname = File.dirname(path)
    name = File.basename(path)
    @source_overrides[dirname]?.try(&.delete(name))
    @source_overrides.delete(dirname)
  end

  # Get the source object at the given path, either an override or real file.
  def get_source_at(path)
    dirname = File.dirname(path)
    name = File.basename(path)
    content = @source_overrides[dirname]?.try(&.[]?(name)) \
      || File.read(to_internal_path(path))
    library = Source::Library.new(dirname)

    Source.new(dirname, name, content, library)
  end

  # Write the given content to the source file at the given path.
  # Note that these changes may not be visible if the real file is being
  # shadowed by a source override (which this operation will not affect).
  def overwrite_source_at(path, content)
    File.write(to_internal_path(path), content)
  end

  # Convert the given path into an "internal path", which corresponds to a
  # real path on the local filesystem, which sometimes may differ from the
  # public-facing path that we use everywhere else during compilation.
  private def to_internal_path(path)
    @main_directory_remap.try do |prefix, internal_prefix|
      next unless path.starts_with?(prefix)
      return path.sub(prefix, internal_prefix)
    end

    @standard_directory_remap.try do |prefix, _|
      next unless path.starts_with?(prefix)
      return path.sub(prefix, @standard_library_internal_path)
    end

    path
  end

  # Convert the given "internal path" into a public-facing path, which
  # corresponds to the path that a user should see when we talk about this path,
  # sometimes differing from the internal path that is on the real filesystem.
  private def from_internal_path(path)
    @main_directory_remap.try do |prefix, internal_prefix|
      next unless path.starts_with?(internal_prefix)
      return path.sub(internal_prefix, prefix)
    end

    @standard_directory_remap.try do |prefix, _|
      next unless path.starts_with?(@standard_library_internal_path)
      return path.sub(@standard_library_internal_path, prefix)
    end

    path
  end

  # Check if the given directory exists, either in reality or in an override.
  private def dir_exists?(dirname)
    internal_dirname = to_internal_path(dirname)
    Dir.exists?(internal_dirname) || @source_overrides.has_key?(dirname)
  end

  # Yield the name and content of each Savi file in this dirname.
  private def each_savi_file_in(dirname)
    dir_source_overrides = @source_overrides[dirname]?
    internal_dirname = to_internal_path(dirname)

    # Yield the real files and their content.
    Dir.entries(internal_dirname).each { |name|
      next unless name.ends_with?(".savi")

      # If this is a filename that has overridden content, omit it for now.
      # We will yield it later when yielding all the other overrides.
      next if dir_source_overrides.try(&.has_key?(name))

      # Try to read the content from the file, or skip it if we fail for any
      # reason, such as filesystem issues or deletion race conditions.
      content = File.read(File.join(internal_dirname, name)) rescue nil
      next unless content

      yield ({name, content})
    }

    # Now yield the fake files implied by the source overrides for this dirname.
    dir_source_overrides.try(&.each { |name, content| yield ({name, content}) })
  end

  # Yield the name and content of each Savi file in this glob pattern.
  private def each_savi_file_in_glob(glob)
    internal_glob = to_internal_path(glob)

    # Yield the glob-matched files and their content.
    Dir.glob(internal_glob).each { |name|
      next unless name.ends_with?(".savi")

      # If this is a filename that has overridden content, omit it for now.
      # We will yield it later when yielding all the other overrides.
      if (dir_overrides = @source_overrides[File.dirname(name)]?) \
      && (override = dir_overrides[File.basename(name)]?)
        yield ({name, override})
      else
        # Try to read the content from the file, or skip it if we fail for any
        # reason, such as filesystem issues or deletion race conditions.
        content = File.read(name) rescue nil
        yield ({name, content}) if content
      end
    }
  end

  # Yield the dirname, name, content of each Savi file in each subdirectory.
  private def each_savi_file_in_recursive(root_dirname)
    internal_root_dirname = to_internal_path(root_dirname)

    # Yield the real files and their content.
    Dir.glob("#{internal_root_dirname}/**/*.savi").each { |internal_path|
      name = File.basename(internal_path)
      internal_dirname = File.dirname(internal_path)
      dirname = from_internal_path(internal_dirname)

      # If this is a filename that has overridden content, omit it for now.
      # We will yield it later when yielding all the other overrides.
      next if @source_overrides[dirname]?.try(&.[]?(name))

      # Try to read the content from the file, or skip it if we fail for any
      # reason, such as filesystem issues or deletion race conditions.
      content = File.read(internal_path) rescue nil
      next unless content

      yield ({dirname, name, content})
    }

    # Now yield the fake files implied by the source overrides for this dirname.
    @source_overrides.each { |dirname, dir_source_overrides|
      next unless dirname.starts_with?(root_dirname)

      dir_source_overrides.each { |name, content|
        yield ({dirname, name, content})
      }
    }
  end

  # Given a library name, optionally anchored to a given "from source",
  # try to resolve a directory that matches the library name.
  #
  # First a relative location will be attempted starting from the "from source".
  # Then a standard library location will be attempted.
  # If both attempts fail, there is no hope of resolving the library.
  def resolve_library_dirname(libname : String, from_source : Source)
    standard_dirname = File.expand_path(libname, standard_library_path)
    relative_dirname = File.expand_path(libname, from_source.dirname)

    if relative_dirname && dir_exists?(relative_dirname)
      relative_dirname
    elsif dir_exists?(standard_dirname)
      standard_dirname
    end
  end

  # Given a directory name, load source objects for all the source files in it.
  def get_library_sources(dirname, library : Source::Library? = nil)
    library ||= Source::Library.new(dirname)

    sources = [] of Source
    each_savi_file_in(dirname) { |name, content|
      sources << Source.new(dirname, name, content, library)
    }

    Error.at Source::Pos.show_library_path(library),
      "No '.savi' source files found in this directory" \
        if sources.empty?

    # Sort the sources by case-insensitive name, so that they always get loaded
    # in a repeatable order regardless of platform implementation details, or
    # the possible presence of source overrides shadowing some of the files.
    sources.sort_by!(&.filename.downcase)

    sources
  end

  # Given a manifest, load source objects for all the source files in its paths.
  def get_sources_for_manifest(ctx, manifest : Packaging::Manifest)
    library = Source::Library.for_manifest(manifest)

    manifest.sources_paths.flat_map { |sources_path|
      sources = [] of Source
      absolute_glob = File.join(library.path, sources_path.value)

      prior_source_size = sources.size
      each_savi_file_in_glob(absolute_glob) { |name, content|
        dirname = File.dirname(name)
        basename = File.basename(name)
        sources << Source.new(dirname, basename, content, library)
      }

      ctx.error_at sources_path,
        "No '.savi' source files found in #{absolute_glob.inspect}" \
          if sources.empty?

      # Sort the sources by case-insensitive name, so that they always get loaded
      # in a repeatable order regardless of platform implementation details, or
      # the possible presence of source overrides shadowing some of the files.
      #
      # Note that we sort each group (from each glob) separately,
      # and concatenate them in order of the globs declaration order, so that
      # the declaration order can be meaningful if desired.
      sources.sort_by!(&.filename.downcase)

      sources
    }
  end

  # Given a directory name, load source objects for all the source files in
  # each subdirectory of that root directory, grouped by source library.
  def get_recursive_sources(root_dirname, language = :savi)
    sources = {} of Source::Library => Array(Source)
    each_savi_file_in_recursive(root_dirname) { |dirname, name, content|
      library = Source::Library.new(dirname)

      (sources[library] ||= [] of Source) \
        << Source.new(dirname, name, content, library)
    }

    Error.at Source::Pos.show_library_path(Source::Library.new(root_dirname)),
      "No '.savi' source files found recursively within this root" \
        if sources.empty?

    # Sort the sources by case-insensitive name, so that they always get loaded
    # in a repeatable order regardless of platform implementation details, or
    # the possible presence of source overrides shadowing some of the files.
    sources.each(&.last.sort_by!(&.filename.downcase))
    sources.to_a.sort_by!(&.first.path.downcase)
  end
end
