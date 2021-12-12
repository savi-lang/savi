struct Savi::Packaging::Manifest
  getter name : AST::Identifier
  getter kind : AST::Identifier
  getter copies_names = [] of AST::Identifier
  getter provides_names = [] of AST::Identifier
  getter sources_paths = [] of AST::LiteralString
  getter dependencies = [] of Dependency

  def initialize(@name, @kind)
  end

  def bin_path
    File.join(name.pos.source.dirname, "bin", name.value)
  end

  def is_main?
    @kind.value == "main"
  end

  def is_lib?
    @kind.value == "lib"
  end

  def is_bin?
    @kind.value == "bin"
  end

  def is_whole_program?
    !is_lib?
  end
end
