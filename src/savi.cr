require "./savi/ext/**"
require "./savi/**"

module Savi
  VERSION = "0.0.1"

  def self.compiler
    Compiler::INSTANCE
  end
end
