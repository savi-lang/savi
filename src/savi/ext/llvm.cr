require "llvm"
require "./llvm/*"

module LLVM
  def self.configured_default_target_triple
    {{ env("LLVM_DEFAULT_TARGET") }} || default_target_triple
  end
end
