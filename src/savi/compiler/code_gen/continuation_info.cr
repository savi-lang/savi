class Savi::Compiler::CodeGen
  class ContinuationInfo
    private getter g : CodeGen
    private getter gtype : GenType
    private getter gfunc : GenFunc

    def initialize(@g, @gtype, @gfunc)
    end

    private def ctx; g.ctx end
    private def builder; g.builder end

    def yield_in_type
      mt = gfunc.reified.meta_type_of_yield_in(ctx, gfunc.infer).not_nil!
      ctx.reach[mt]
    end

    def yield_in_llvm_type
      g.llvm_type_of(yield_in_type)
    end

    def self.virtual_struct_type(g, concrete_gfuncs)
      concrete_infos = concrete_gfuncs.map(&.continuation_info)

      # We don't yet support the case where the public elements of the
      # continuation data do not match - they would need to be boxed/unboxed
      # in a wrapper virtual function, which we don't yet have code for.
      public_elements_uniq = concrete_infos
        .map(&.struct_element_types.[0...3].as(Array(LLVM::Type))).uniq
      public_elements_match = public_elements_uniq.one?
      raise NotImplementedError.new \
        "heterogenous public members of virtual continuation types: #{
          public_elements_uniq
        }" \
          unless public_elements_match

      # Create a virtual continuation struct type which has all of the
      # public elements, and is padded with extra intptrs until its size
      # is at least as large as all of the concrete_infos require in memory.
      public_elements =
        concrete_infos.first.struct_element_types[0...3]
      virtual_t = g.llvm.struct(public_elements)
      while concrete_infos.any? { |concrete|
        g.abi_size_of(concrete.struct_type) > g.abi_size_of(virtual_t)
      }
        virtual_t = g.llvm.struct(virtual_t.struct_element_types + [g.isize])
      end
      virtual_t
    end

    @struct_type : LLVM::Type?
    def struct_type
      @struct_type || begin
        @struct_type = struct_type =
          g.llvm.struct_create_named("#{gfunc.llvm_name.gsub("!", "")}.CONTINUATION")
        struct_type.struct_set_body(struct_element_types)
        struct_type
      end.not_nil!
    end

    @struct_element_types : Array(LLVM::Type)?
    def struct_element_types
      (@struct_element_types ||= begin
        list = [] of LLVM::Type

        # The first element is always the next yield index to use.
        # This is zero when the function is called the first time,
        # 0xffff when the function is finished, or 0xfffe if it errored.
        list << g.llvm.int16

        # Then comes the final return value.
        list << g.llvm_type_of(gfunc.reach_func.signature.ret)

        # Then comes the yield out values (as elements of a nested struct).
        list << g.llvm.struct(
          gfunc.reach_func.signature.yield_out.map do |yield_out_ref|
            g.llvm_type_of(yield_out_ref)
          end
        )

        # Then come the local variables.
        ctx.inventory[gfunc.link].each_local.each do |ref|
          ref_defn = ctx.local[gfunc.link].any_initial_site_for(ref).node
          list << g.llvm_mem_type_of(ref_defn, gfunc)
        end

        # Then come the nested yielding call continuations.
        # These exist when there is a yield block within another yield block.
        nested_cont_struct_types.each do |cont_type|
          # If this yielding function contains a recursive call to itself,
          # we won't know what struct size to allocate, and thus need to
          # make an indirection by turning this into a pointer element,
          # which can no longer be stack allocated and must be heap allocated.
          cont_type = cont_type.pointer \
            if CodeGen.recursively_contains_direct_struct_type?(cont_type, struct_type)

          list << cont_type
        end
        # And the yielding call receivers that go with each continuation.
        ctx.inventory[gfunc.link].each_yielding_call.each do |call|
          list << g.llvm_type_of(call.receiver, gfunc)
        end

        list
      end).not_nil!
    end

    @nested_cont_struct_types : Array(LLVM::Type)?
    def nested_cont_struct_types
      (@nested_cont_struct_types ||= begin
        list = [] of LLVM::Type

        ctx.inventory[gfunc.link].each_yielding_call.each do |call|
          list << g.resolve_yielding_call_cont_type(call, gfunc, gfunc)
        end

        list
      end).not_nil!
    end

    def struct_gep_for_next_yield_index(cont : LLVM::Value)
      builder.struct_gep(struct_type, cont, 0, "CONT.NEXT.GEP")
    end

    def get_next_yield_index(cont : LLVM::Value)
      next_yield_index_gep = struct_gep_for_next_yield_index(cont)
      builder.load(struct_element_types[0], next_yield_index_gep, "CONT.NEXT")
    end

    def set_next_yield_index(cont : LLVM::Value, next_yield_index : Int32)
      raise "next_yield_index too high" if next_yield_index >= 0xfffe

      builder.store(
        g.llvm.int16.const_int(next_yield_index),
        struct_gep_for_next_yield_index(cont),
      )
    end

    def set_as_error(cont : LLVM::Value)
      raise "this calling convention can't error" \
        unless gfunc.calling_convention.is_a?(GenFunc::YieldingErrorable)

      # Assign a value of 0xfffe to the continuation's function pointer,
      # signifying the end of the call, with an error for the caller to raise.
      builder.store(
        g.llvm.int16.const_int(0xfffe),
        struct_gep_for_next_yield_index(cont),
      )
    end

    def set_as_finished(cont : LLVM::Value)
      # Assign a value of 0xffff to the continuation's function pointer,
      # signifying the final end of the yielding call.
      builder.store(
        g.llvm.int16.const_int(0xffff),
        struct_gep_for_next_yield_index(cont),
      )
    end

    def struct_gep_for_local(cont : LLVM::Value, ref : Refer::Local)
      index = 3
      index += ctx.inventory[gfunc.link].each_local.index(ref).not_nil!

      builder.struct_gep(struct_type, cont, index, "CONT.#{ref.name}.GEP")
    end

    def call_index_for_yielding_call_cont(call : AST::Call)
      ctx.inventory[gfunc.link].each_yielding_call.index(call).not_nil!
    end

    def struct_index_for_yielding_call_cont(call : AST::Call)
      index = 3
      index += ctx.inventory[gfunc.link].local_count
      index += call_index_for_yielding_call_cont(call)
      index
    end

    def struct_gep_for_yielding_call_cont(cont : LLVM::Value, call : AST::Call)
      index = struct_index_for_yielding_call_cont(call)
      gep = builder.struct_gep(struct_type, cont, index, "CONT.#{call.ident.value}.NESTED.CONT.GEP")

      # If this is a recursive-yielding call with a heap allocation indirection
      # we need an extra load indirection here.
      if struct_type.struct_element_types[index].kind == LLVM::Type::Kind::Pointer
        gep = builder.load(g.ptr, gep, gep.name)
      end

      gep
    end

    def struct_gep_for_yielding_call_receiver(cont : LLVM::Value, call : AST::Call)
      index = 3
      index += ctx.inventory[gfunc.link].local_count
      index += ctx.inventory[gfunc.link].each_yielding_call.size
      index += ctx.inventory[gfunc.link].each_yielding_call.index(call).not_nil!

      builder.struct_gep(struct_type, cont, index, "CONT.#{call.ident.value}.NESTED.RECEIVER.GEP")
    end

    def each_struct_index_for_yielding_call_conts
      index = 3
      index += ctx.inventory[gfunc.link].local_count;         from_index = index
      index += ctx.inventory[gfunc.link].yielding_call_count; upto_index = index

      from_index...upto_index
    end

    def check_is_error(cont : LLVM::Value)
      # Check if next_yield_index was set to the error value by set_as_error.
      builder.icmp(LLVM::IntPredicate::EQ,
        get_next_yield_index(cont),
        g.llvm.int16.const_int(0xfffe),
      )
    end

    def check_is_finished(cont : LLVM::Value)
      case gfunc.calling_convention
      when GenFunc::Yielding
        # Check if next_yield_index was set to finished by set_as_finished.
        builder.icmp(LLVM::IntPredicate::EQ,
          get_next_yield_index(cont),
          g.llvm.int16.const_int(0xffff),
        )
      when GenFunc::YieldingErrorable
        # Check if next_yield_index was set to error or finished.
        builder.icmp(LLVM::IntPredicate::UGE,
          get_next_yield_index(cont),
          g.llvm.int16.const_int(0xfffe),
        )
      else
        raise NotImplementedError.new("#{gfunc.calling_convention}")
      end
    end

    def struct_gep_for_final_return(cont : LLVM::Value)
      builder.struct_gep(struct_type, cont, 1, "CONT.FINAL.GEP")
    end

    def get_final_return(cont : LLVM::Value)
      type = struct_element_types[1]
      builder.load(type, struct_gep_for_final_return(cont), "CONT.FINAL")
    end

    def set_final_return(cont : LLVM::Value, value : LLVM::Value)
      builder.store(value, struct_gep_for_final_return(cont))
    end

    def struct_type_for_yield_out
      struct_element_types[2]
    end

    def struct_gep_for_yield_out(cont : LLVM::Value)
      builder.struct_gep(struct_type, cont, 2, "CONT.YIELDOUT.GEP")
    end

    def get_yield_out(cont : LLVM::Value)
      type = struct_element_types[2]
      builder.load(type, struct_gep_for_yield_out(cont), "CONT.YIELDOUT")
    end

    def set_yield_out(cont : LLVM::Value, value : LLVM::Value)
      builder.store(value, struct_gep_for_yield_out(cont))
    end

    def on_func_start(frame : Frame, is_continue : Bool)
      # Grab the continuation value from the first parameter,
      # skipping the receiver if present in this call.
      cont_param_index = 0
      cont_param_index += 1 if gfunc.needs_receiver?
      cont = frame.continuation_value = frame.llvm_func.params[cont_param_index]

      unless is_continue
        ctx.inventory[gfunc.link].each_yielding_call.each_with_index do |call, call_index|
          struct_index = struct_index_for_yielding_call_cont(call)
          nested_cont_type = struct_element_types[struct_index]
          next unless nested_cont_type.kind == LLVM::Type::Kind::Pointer

          nested_cont_struct_type = nested_cont_struct_types[call_index]

          # We have a recursive nested cont that we need to heap-allocate.
          builder.store(
            g.gen_alloc_struct(nested_cont_struct_type, "#{cont.name}.NEST.#{struct_index}"),
            builder.struct_gep(struct_type, cont, struct_index, "#{cont.name}.NEST.#{struct_index}.GEP"),
          )
        end
      end

      # We need to eagerly generate the local geps here in the entry block,
      # since if we generate them lazily, they may not dominate all uses
      # in the LLVM dominator tree analysis (which checks declare-before-use).
      ctx.inventory[gfunc.link].each_local.each_with_index do |ref, ref_index|
        ref_index = ref_index + 1 # skip the first element - the next yield index
        ref_index = ref_index + 1 # skip the next element - the final return
        ref_index = ref_index + 1 # skip the next element - the yield out values
        ref_type = struct_element_types[ref_index]
        local = g.gen_local_alloca(ref, ref_type)

        # If this is a continue function resuming where we left off,
        # then we also need to restore the value of each local variable.
        if is_continue
          ref_defn = ctx.local[gfunc.link].any_initial_site_for(ref).node
          cont_local = gfunc.continuation_info.struct_gep_for_local(cont, ref)
          builder.store(
            builder.load(g.llvm_type_of(ref_defn), cont_local, "#{ref.name}.RESTORED"),
            local
          )
        end
      end

      # Eagerly create struct geps for all yielding call continuations
      # and receivers that are nested in this yielding function func.
      ctx.inventory[gfunc.link].each_yielding_call.each do |call|
        frame.yielding_call_conts[call] = struct_gep_for_yielding_call_cont(cont, call)
        frame.yielding_call_receivers[call] = struct_gep_for_yielding_call_receiver(cont, call)
      end
    end

    def jump_according_to_next_yield_index(frame : Frame, after_yield_blocks)
      # Create a block that handles the case where the yield index is invalid.
      invalid_block = g.gen_block("yield_index_invalid")

      # Create a switch that chooses which after_yield_block to jump to,
      # based on the value of the next_yield_index in the continuation data.
      cases = {} of LLVM::Value => LLVM::BasicBlock
      after_yield_blocks.each_with_index do |after_yield_block, index|
        cases[g.llvm.int16.const_int(index)] = after_yield_block
      end
      builder.switch(
        get_next_yield_index(frame.continuation_value),
        invalid_block,
        cases,
      )

      # None of the above yield indexes matched. This should never happen.
      g.finish_block_and_move_to(invalid_block)
      builder.unreachable
    end
  end
end
