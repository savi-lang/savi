require "compiler/crystal/codegen/target"

class Savi::Compiler::Target < Crystal::Codegen::Target
  def arm64?
    architecture == "aarch64"
  end

  def x86_64?
    architecture == "x86_64"
  end
end
