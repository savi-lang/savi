struct Savi::Packaging::Manifest
  getter name : AST::Identifier
  getter kind : AST::Identifier
  getter copies_names = [] of AST::Identifier
  getter sources_paths = [] of AST::LiteralString
  getter dependencies = [] of Dependency

  def initialize(@name, @kind)
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
