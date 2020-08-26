require "./mare/ext/**"
require "./mare/**"

module Mare
  VERSION = "0.0.1"

  def self.compiler
    Compiler::INSTANCE
  end
end
