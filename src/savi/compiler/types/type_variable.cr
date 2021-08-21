module Savi::Compiler::Types
  class TypeVariable
    getter nickname : String
    getter scope : Program::Function::Link | Program::Type::Link | Program::TypeAlias::Link
    getter sequence_number : UInt64
    property is_cap_var : Bool
    def initialize(@nickname, @scope, @sequence_number, @is_cap_var = false)
    end

    def show_name
      kind_sym = @is_cap_var ? 'K' : 'T'
      scope_sym = scope.is_a?(Program::Function::Link) ? "'" : "'^"
      "#{kind_sym}'#{@nickname}#{scope_sym}#{@sequence_number}"
    end
  end
end
