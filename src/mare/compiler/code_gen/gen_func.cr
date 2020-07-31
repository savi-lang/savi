class Mare::Compiler::CodeGen
  class GenFunc
    getter func : Program::Function
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
      @func = @reach_func.reified.link.resolve(ctx)
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
      raise NotImplementedError.new(list)
    end

    def type_def
      @reach_func.reach_def
    end

    def infer
      @reach_func.infer
    end

    def link
      @reach_func.reified.link
    end

    def needs_receiver?
      @needs_receiver
    end

    def needs_continuation?(ctx)
      calling_convention.needs_continuation?
    end

    def needs_send?
      func.has_tag?(:async)
    end

    def is_initializer?
      func.has_tag?(:field) && !func.body.nil?
    end

    abstract class CallingConvention
      abstract def needs_continuation? : Bool
      abstract def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type
    end

    class Simple < CallingConvention
      INSTANCE = new

      def needs_continuation? : Bool; false end

      def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type
        g.llvm_type_of(gfunc.reach_func.signature.ret)
      end
    end

    class Constructor < CallingConvention
      INSTANCE = new

      def needs_continuation? : Bool; false end

      def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type
        g.llvm.void
      end
    end

    class Errorable < CallingConvention
      INSTANCE = new

      def needs_continuation? : Bool; false end

      def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type
        g.llvm.struct([
          g.llvm_type_of(gfunc.reach_func.signature.ret),
          g.llvm.int1,
        ])
      end
    end

    class Yielding < CallingConvention
      INSTANCE = new

      def needs_continuation? : Bool; true end

      def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type
        g.llvm.void
      end
    end

    class YieldingErrorable < CallingConvention
      INSTANCE = new

      def needs_continuation? : Bool; true end

      def llvm_func_ret_type(g : CodeGen, gfunc : GenFunc) : LLVM::Type
        g.llvm.void
      end
    end
  end
end
