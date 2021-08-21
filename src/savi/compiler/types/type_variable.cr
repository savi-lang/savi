module Savi::Compiler::Types
  class TypeVariable
    getter nickname : String
    getter scope : Program::Function::Link | Program::Type::Link | Program::TypeAlias::Link
    getter sequence_number : UInt64
    property is_cap_var : Bool

    def initialize(@nickname, @scope, @sequence_number, @is_cap_var = false)
      @bindings = Set({Source::Pos, AlgebraicType}).new
      @constraints = Set({Source::Pos, AlgebraicType}).new
      @assignments = Set({Source::Pos, AlgebraicType}).new
      @from_call_returns = Set({Source::Pos, AST::Call, AlgebraicType}).new
    end

    protected def observe_constraint_at(
      pos : Source::Pos,
      supertype : AlgebraicType,
    )
      @constraints << {pos, supertype}
    end

    protected def observe_binding_at(
      pos : Source::Pos,
      type : AlgebraicType,
    )
      @bindings << {pos, type}
    end

    protected def observe_assignment_at(
      pos : Source::Pos,
      subtype : AlgebraicType,
    )
      @assignments << {pos, subtype}
    end

    protected def observe_from_call_return_at(
      pos : Source::Pos,
      call : AST::Call,
      receiver_type : AlgebraicType,
    )
      @from_call_returns << {pos, call, receiver_type}
    end

    def show_name
      kind_sym = @is_cap_var ? 'K' : 'T'
      scope_sym = scope.is_a?(Program::Function::Link) ? "'" : "'^"
      "#{kind_sym}'#{@nickname}#{scope_sym}#{@sequence_number}"
    end

    def show_info(output)
      output << "#{self.show_name}\n"
      @bindings.each { |pos, explicit|
        output << "  := #{explicit.show}\n"
        output << "  #{pos.show.split("\n")[1..-1].join("\n  ")}\n"
      }
      @constraints.each { |pos, sup|
        output << "  <: #{sup.show}\n"
        output << "  #{pos.show.split("\n")[1..-1].join("\n  ")}\n"
      }
      @assignments.each { |pos, sub|
        output << "  :> #{sub.show}\n"
        output << "  #{pos.show.split("\n")[1..-1].join("\n  ")}\n"
      }
      @from_call_returns.each { |pos, call, receiver_type|
        output << "  :> #{receiver_type.show}.#{call.ident.value}\n"
        output << "  #{pos.show.split("\n")[1..-1].join("\n  ")}\n"
      }
    end
  end
end
