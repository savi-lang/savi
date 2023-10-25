require "compiler/crystal/codegen/target"

class Savi::Compiler::Target < Crystal::Codegen::Target
  def any_arm?
    architecture == "arm" || architecture == "aarch64"
  end

  def any_x86?
    architecture == "i386" || architecture == "x86_64"
  end

  def arm64?
    architecture == "aarch64"
  end

  def x86_64?
    architecture == "x86_64"
  end
end
