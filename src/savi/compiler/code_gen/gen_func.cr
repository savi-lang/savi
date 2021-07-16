class Savi::Compiler::CodeGen
  class GenFunc
    getter func : Program::Function
    getter infer : Infer::FuncAnalysis
    getter reach_func : Reach::Func
    getter calling_convention : CallingConvention
    getter! continuation_info : ContinuationInfo
    getter! vtable_index : Int32
    getter! vtable_index_continue : Int32
    getter llvm_name : String
    property! llvm_func : LLVM::Function
    property! llvm_func_ret_type : LLVM::Type
    property! virtual_llvm_func : LLVM::Function
    property! send_llvm_func : LLVM::Function
    property! send_msg_llvm_type : LLVM::Type
    property continue_llvm_func : LLVM::Function?
    property! virtual_continue_llvm_func : LLVM::Function?
    property! after_yield_blocks : Array(LLVM::BasicBlock)

    def initialize(ctx, gtype, @reach_func, @vtable_index, @vtable_index_continue)
      link = @reach_func.reified.link
      @func = link.resolve(ctx)
      @infer = ctx.infer[link]
      @needs_receiver = type_def.has_state?(ctx) && !(func.cap.value == "non")

      @llvm_name = "#{type_def.llvm_name}#{@reach_func.reified.name}"
      @llvm_name = "#{@llvm_name}.HYGIENIC" if link.hygienic_id

      @calling_convention = self.class.calling_convention_for(ctx, func, link)
      @continuation_info = ContinuationInfo.new(ctx.code_gen, gtype, self)
    end

    def self.calling_convention_for(ctx, func, link) : CallingConvention
      list = [] of CallingConvention
      list << Constructor::INSTANCE if func.has_tag?(:constructor)
      list << Errorable::INSTANCE if ctx.jumps[link].any_error?(func.ident)
      list << Yielding::INSTANCE if ctx.inventory[link].yield_count > 0

      return Simple::INSTANCE if list.empty?
      return list.first if list.size == 1
      return YieldingErrorable::INSTANCE if list == [Errorable::INSTANCE, Yielding::INSTANCE]
      return Errorable::INSTANCE if list == [Constructor::INSTANCE, Errorable::INSTANCE]
      raise NotImplementedError.new(list)
    end

    def type_def
      @reach_func.reach_def
    end

    def reified
      @reach_func.reified
    end

    def type_check
      @reach_func.type_check
    end

    def link
      @reach_func.reified.link
    end

    def needs_receiver?
      @needs_receiver
    end

    def boxed_fields_receiver?(ctx)
      @needs_receiver \
      && type_def.is_pass_by_value?(ctx) \
      && (
        func.has_tag?(:constructor) \
        || (func.has_tag?(:let) && func.ident.value.ends_with?("=")) # TODO: less hacky as a special case somehow?
      )
    end

    def can_error?
      calling_convention.can_error?
    end

    def needs_continuation?
      calling_convention.needs_continuation?
    end

    def needs_send?
      func.has_tag?(:async)
    end

    def is_initializer?
      func.has_tag?(:field) && !func.body.nil?
    end

    abstract class CallingConvention
      abstract def can_error? : Bool
      abstract def needs_continuation? : Bool
      abstract def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type

      abstract def gen_return(g : CodeGen, gfunc : GenFunc, value : LLVM::Value, value_expr : AST::Node?)
      def gen_error_return(g : CodeGen, gfunc : GenFunc, value : LLVM::Value, value_expr : AST::Node?)
        raise NotImplementedError.new("gen_error_return for #{self}")
      end
      def gen_yield_return(g : CodeGen, gfunc : GenFunc, yield_index : Int32, values : Array(LLVM::Value), value_exprs : Array(AST::Node?))
        raise NotImplementedError.new("gen_yield_return for #{self}")
      end
    end

    class Simple < CallingConvention
      INSTANCE = new

      def can_error? : Bool; false end
      def needs_continuation? : Bool; false end

      def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type
        g.llvm_type_of(gfunc.reach_func.signature.ret)
      end

      def gen_return(g : CodeGen, gfunc : GenFunc, value : LLVM::Value, value_expr : AST::Node?)
        if value_expr
          value_type = gfunc.reach_func.signature.ret
          value = g.gen_assign_cast(value, value_type, value_expr)
        end
        g.builder.ret(value)
      end
    end

    class Constructor < CallingConvention
      INSTANCE = new

      def can_error? : Bool; false end
      def needs_continuation? : Bool; false end

      def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type
        g.llvm.void
      end

      def gen_return(g : CodeGen, gfunc : GenFunc, value : LLVM::Value, value_expr : AST::Node?)
        g.builder.ret
      end
    end

    class Errorable < CallingConvention
      INSTANCE = new

      def can_error? : Bool; true end
      def needs_continuation? : Bool; false end

      def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type
        g.llvm.struct([
          g.llvm_type_of(gfunc.reach_func.signature.ret),
          g.llvm.int1,
        ])
      end

      def gen_return(g : CodeGen, gfunc : GenFunc, value : LLVM::Value, value_expr : AST::Node?)
        if value_expr
          value_type = gfunc.reach_func.signature.ret
          value = g.gen_assign_cast(value, value_type, value_expr)
        end
        tuple = llvm_func_ret_type(g, gfunc).undef
        tuple = g.builder.insert_value(tuple, value, 0)
        tuple = g.builder.insert_value(tuple, g.llvm.int1.const_int(0), 1)
        g.builder.ret(tuple)
      end

      def gen_error_return(g : CodeGen, gfunc : GenFunc, value : LLVM::Value, value_expr : AST::Node?)
        tuple = llvm_func_ret_type(g, gfunc).undef
        tuple = g.builder.insert_value(tuple, value, 0)
        tuple = g.builder.insert_value(tuple, g.llvm.int1.const_int(1), 1)
        g.builder.ret(tuple)
      end
    end

    class Yielding < CallingConvention
      INSTANCE = new

      def can_error? : Bool; false end
      def needs_continuation? : Bool; true end

      def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type
        g.llvm.void
      end

      def gen_return(g : CodeGen, gfunc : GenFunc, value : LLVM::Value, value_expr : AST::Node?)
        if value_expr
          value_type = gfunc.reach_func.signature.ret
          value = g.gen_assign_cast(value, value_type, value_expr)
        end
        cont = g.func_frame.continuation_value
        gfunc.continuation_info.set_as_finished(cont)
        gfunc.continuation_info.set_final_return(cont, value)
        g.builder.ret
      end

      def gen_yield_return(g : CodeGen, gfunc : GenFunc, yield_index : Int32, values : Array(LLVM::Value), value_exprs : Array(AST::Node?))
        # Cast the given values to the appropriate type.
        cast_values =
          values.zip(value_exprs).map_with_index do |(value, value_expr), index|
            next value unless value_expr
            cast_type = gfunc.reach_func.signature.yield_out[index]
            g.gen_assign_cast(value, cast_type, value_expr)
          end

        # Grab the continuation value from local memory and set the next func.
        # Also set the tuple of yield out values into the continuation data.
        cont = g.func_frame.continuation_value
        tuple = gfunc.continuation_info.struct_type_for_yield_out.undef
        tuple.name = "YIELDOUT"
        cast_values.each_with_index do |cast_value, index|
          tuple = g.builder.insert_value(tuple, cast_value, index)
        end
        gfunc.continuation_info.set_yield_out(cont, tuple)
        gfunc.continuation_info.set_next_yield_index(cont, yield_index)

        # Return void.
        g.builder.ret
      end
    end

    class YieldingErrorable < CallingConvention
      INSTANCE = new

      def can_error? : Bool; true end
      def needs_continuation? : Bool; true end

      def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type
        g.llvm.void
      end

      def gen_return(g : CodeGen, gfunc : GenFunc, value : LLVM::Value, value_expr : AST::Node?)
        if value_expr
          value_type = gfunc.reach_func.signature.ret
          value = g.gen_assign_cast(value, value_type, value_expr)
        end
        cont = g.func_frame.continuation_value
        gfunc.continuation_info.set_as_finished(cont)
        gfunc.continuation_info.set_final_return(cont, value)
        g.builder.ret
      end

      def gen_error_return(g : CodeGen, gfunc : GenFunc, value : LLVM::Value, value_expr : AST::Node?)
        cont = g.func_frame.continuation_value
        gfunc.continuation_info.set_as_error(cont)
        g.builder.ret
      end

      def gen_yield_return(g : CodeGen, gfunc : GenFunc, yield_index : Int32, values : Array(LLVM::Value), value_exprs : Array(AST::Node?))
        # Delegate to the sister class that is the same in this respect.
        Yielding::INSTANCE.gen_yield_return(g, gfunc, yield_index, values, value_exprs)
      end
    end
  end
end
