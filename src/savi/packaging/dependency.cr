struct Savi::Packaging::Dependency
  getter name : AST::Identifier
  getter version_node : AST::LiteralString
  getter version_major : Int32
  getter version_minor : Int32
  getter version_patch : Int32

  getter location_nodes = [] of AST::Identifier
  getter revision_nodes = [] of AST::Identifier
  getter depends_on_nodes = [] of AST::Identifier

  def initialize(@name, @version_node, @transitive = false)
    @version_major = 0 # TODO
    @version_minor = 0 # TODO
    @version_patch = 0 # TODO
  end

  def transitive?
    @transitive
  end
end
