# TODO: Bring in "crystal/src/compiler/crystal/codegen/target.cr"
class Mare::Compiler::Target
  def initialize(@target_triple : String)
  end

  def freebsd?
    @target_triple.downcase.split("-").any? { |part| part.starts_with?("freebsd") }
  end
end
