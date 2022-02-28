struct Savi::Packaging::Dependency
  getter ast : AST::Declare
  getter name : AST::Identifier
  getter version : AST::Identifier

  getter location_nodes = [] of AST::LiteralString
  getter revision_nodes = [] of AST::Identifier
  getter depends_on_nodes = [] of AST::Identifier

  def initialize(@ast, @name, @version, @transitive = false)
  end

  def transitive?
    @transitive
  end

  def accepts_version?(version : String)
    expected = @version.value
    version == expected || (version.starts_with?("#{expected}."))
  end

  def location
    location_nodes.first?.try(&.value) || ""
  end

  def location_scheme : String
    location = location()
    return "" unless location.includes?(":")

    location.split(":", 2).first
  end

  def location_without_scheme : String
    location = location()
    return location unless location.includes?(":")

    location.split(":", 2).last
  end
end
