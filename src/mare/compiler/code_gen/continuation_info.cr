class Mare::Compiler::CodeGen
  class ContinuationInfo
    private getter g : CodeGen
    private getter gtype : GenType
    private getter gfunc : GenFunc
    
    def initialize(@g, @gtype, @gfunc)
    end
    
    private def ctx; g.ctx end
    private def builder; g.builder end
    
    @struct_element_types : Array(LLVM::Type)?
    def struct_element_types
      (@struct_element_types ||= (
        list = [] of LLVM::Type
        list << gfunc.continuation_llvm_func_ptr
        list << g.llvm_type_of(gtype) if gfunc.needs_receiver?
        list.concat \
          ctx.inventory.locals[gfunc.func].map { |ref| g.llvm_mem_type_of(ref.defn, gfunc) }
        list
      )).not_nil!
    end
    
    def struct_index_of_receiver
      raise "no receiver for this gfunc" unless gfunc.needs_receiver?
      1
    end
    
    def struct_index_of_local(ref : Refer::Local)
      index = 1
      index += 1 if gfunc.needs_receiver?
      index += ctx.inventory.locals[gfunc.func].index(ref).not_nil!
    end
    
    def struct_gep_for_receiver(cont : LLVM::Value)
      builder.struct_gep(cont, struct_index_of_receiver, "CONT.@.GEP")
    end
    
    def struct_gep_for_local(cont : LLVM::Value, ref : Refer::Local)
      builder.struct_gep(cont, struct_index_of_local(ref), "CONT.#{ref.name}.GEP")
    end
    
    def gen_local_geps
      ctx.inventory.locals[gfunc.func].each_with_index do |ref, ref_index|
        ref_index = ref_index + 1 # skip the first element - the next func
        ref_index = ref_index + 1 if gfunc.needs_receiver? # skip the receiver
        ref_type = struct_element_types[ref_index]
        yield ref, g.gen_local_gep(ref, ref_type)
      end
    end
    
    def get_next_func(cont : LLVM::Value)
      next_func_gep = builder.struct_gep(cont, 0, "CONT.NEXT.GEP")
      builder.load(next_func_gep, "CONT.NEXT")
    end
    
    def set_next_func(cont : LLVM::Value, next_func : LLVM::Value?)
      next_func_gep = builder.struct_gep(cont, 0, "CONT.NEXT.GEP")
      
      # Assign the next continuation function to the function pointer.
      # If nil, then we assign a NULL pointer, signifying the final return value,
      # telling the caller not to continue the yield block iteration any more.
      if next_func
        next_func = builder.bit_cast(next_func, gfunc.continuation_llvm_func_ptr, "#{next_func.name}.GENERIC")
        builder.store(next_func, next_func_gep)
      else
        # Assign NULL to the continuation's function pointer, signifying the end.
        builder.store(gfunc.continuation_llvm_func_ptr.null, next_func_gep)
      end
    end
    
    def check_next_func_is_null(cont : LLVM::Value)
      null = gfunc.continuation_llvm_func_ptr.null
      builder.icmp(LLVM::IntPredicate::EQ, get_next_func(cont), null)
    end
  end
end
