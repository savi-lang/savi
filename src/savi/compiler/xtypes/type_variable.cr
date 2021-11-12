module Savi::Compiler::XTypes
  class TypeVariable
    alias Scope = Program::Function::Link | Program::Type::Link | Program::TypeAlias::Link
    getter nickname : String
    getter scope : Scope
    getter sequence_number : UInt64
    property is_cap_var : Bool
    property is_input_var : Bool = false
    property eager_constraint_summary : AlgebraicType?

    @binding : {Source::Pos, AlgebraicType}?

    def initialize(@nickname, @scope, @sequence_number, @is_cap_var = false)
      @constraints = Set({Source::Pos, AlgebraicType}).new
      @suggested_supertypes = Set({Source::Pos, AlgebraicType}).new
      @assignments = Set({Source::Pos, AlgebraicType}).new
      @from_call_returns = Set({Source::Pos, AST::Call, AlgebraicType}).new
      @toward_call_args = Set({Source::Pos, AST::Call, AlgebraicType, Int32}).new
    end

    protected def observe_constraint_at(
      pos : Source::Pos,
      supertype : AlgebraicType,
      maybe = false,
      via_reciprocal = false,
    )
      if maybe
        @suggested_supertypes << {pos, supertype}
      else
        @constraints << {pos, supertype}
      end

      return if via_reciprocal
      # TODO: observe_constraint_reciprocals?
    end

    protected def observe_binding_at(
      pos : Source::Pos,
      type : AlgebraicType,
    )
      raise "this type variable already has a binding" if @binding
      @binding = {pos, type}
      @eager_constraint_summary = type
    end

    protected def observe_assignment_at(
      pos : Source::Pos,
      subtype : AlgebraicType,
      via_reciprocal = false,
    )
      @assignments << {pos, subtype}

      return if via_reciprocal
      subtype.observe_assignment_reciprocals(pos, TypeVariableRef.new(self))
    end

    protected def observe_from_call_return_at(
      pos : Source::Pos,
      call : AST::Call,
      receiver_type : AlgebraicType,
    )
      @from_call_returns << {pos, call, receiver_type}
    end

    protected def observe_toward_call_arg_at(
      pos : Source::Pos,
      call : AST::Call,
      receiver_type : AlgebraicType,
      arg_num : Int32,
    )
      @toward_call_args << {pos, call, receiver_type, arg_num}
    end

    def show_name
      kind_sym = @is_cap_var ? 'K' : 'T'
      scope_sym = scope.is_a?(Program::Function::Link) ? "'" : "'^"
      "#{kind_sym}'#{@nickname}#{scope_sym}#{@sequence_number}"
    end

    def show_info
      String.build { |output| show_info(output) }
    end
    def show_info(output)
      output << "#{self.show_name}\n"
      @binding.try { |pos, explicit|
        output << "  := #{explicit.show}\n"
        output << "  #{pos.show.split("\n")[1..-1].join("\n  ")}\n"
      }
      @constraints.each { |pos, sup|
        output << "  <: #{sup.show}\n"
        output << "  #{pos.show.split("\n")[1..-1].join("\n  ")}\n"
      }
      @suggested_supertypes.each { |pos, sup|
        output << "  ?<: #{sup.show}\n"
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
      @toward_call_args.each { |pos, call, receiver_type, num|
        output << "  <: #{receiver_type.show}.#{call.ident.value}(#{num})\n"
        output << "  #{pos.show.split("\n")[1..-1].join("\n  ")}\n"
      }
    end

    def trace_as_constraint(cursor : Cursor)
      if @binding
        pos, type = @binding.not_nil!
        cursor.current_pos = pos
        type.trace_as_constraint(cursor)
        return
      end
      if @eager_constraint_summary
        type = @eager_constraint_summary.not_nil! # TODO: add a pos as well?
        type.trace_as_constraint(cursor)
        return
      end

      @constraints.each { |pos, supertype|
        cursor.current_pos = pos
        supertype.trace_as_constraint(cursor)
      }
      # TODO: also trace suggested_supertypes?
      # TODO: also trace toward_call_args?
    end

    def trace_as_assignment(cursor : Cursor)
      if @binding
        pos, type = @binding.not_nil!
        cursor.current_pos = pos
        type.trace_as_assignment(cursor)
        return
      end

      @assignments.each { |pos, subtype|
        cursor.current_pos = pos
        subtype.trace_as_assignment(cursor)
      }
      @from_call_returns.each { |pos, call, receiver|
        cursor.current_pos = pos
        cursor.trace_call_return_as_assignment(pos, call, receiver)
      }

      # TODO: What condition is most appropriate here?
      if is_input_var
        # TODO: Is there a source pos we can use here?
        cursor.add_fact(Source::Pos.none, TypeVariableRef.new(self))
      end
    end

    def calculate_assignment_summary(analysis : Analysis, cursor : Cursor)
      analysis.calculate_assignment_summary(self) {
        next @binding.not_nil!.last if @binding

        @assignments.each { |pos, sub|
          cursor.current_pos = pos
          sub.trace_as_assignment(cursor)
        }
        @from_call_returns.each { |pos, call, receiver|
          cursor.current_pos = pos
          cursor.trace_call_return_as_assignment(pos, call, receiver)
        }

        union_type = nil
        cursor.each_fact { |pos, type|
          if union_type
            union_type = union_type.unite(type)
          else
            union_type = type
          end
        }

        union_type.not_nil! # TODO: nice error for having no assignment facts
      }
    end

    def calculate_constraint_summary(analysis : Analysis, cursor : Cursor)
      analysis.calculate_constraint_summary(self) {
        next @binding.not_nil!.last if @binding
        next @eager_constraint_summary.not_nil! if @eager_constraint_summary

        if @constraints.any?
          @constraints.each { |pos, sup| sup.trace_as_constraint(cursor) }
        end

        intersect_type = nil
        cursor.each_fact { |pos, type|
          if intersect_type
            intersect_type = intersect_type.intersect(type)
          else
            intersect_type = type
          end
        }

        intersect_type.not_nil! # TODO: nice error for having no assignment facts
      }
    end
  end
end
