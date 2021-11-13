require "compiler/crystal/codegen/target"

class Savi::Compiler::Target < Crystal::Codegen::Target
  # TODO: Remove this hack when the upstream llvm-static libraries report
  # the correct environment - currently they report `gnu` on alpine.
  def musl?
    linux? && `ldd --version 2>&1`.starts_with?("musl")
  end
end
