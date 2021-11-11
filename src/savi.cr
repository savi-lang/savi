require "./savi/ext/**"
require "./savi/**"

module Savi
  VERSION = {{ env("SAVI_VERSION") || "unknown" }}
  LLVM_VERSION = {{ env("SAVI_LLVM_VERSION") || "unknown" }}

  def self.compiler
    Compiler::INSTANCE
  end
end
