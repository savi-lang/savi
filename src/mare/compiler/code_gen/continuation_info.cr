class Mare::Compiler::CodeGen
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
      g.llvm_type_of(ctx.reach[mt])
    end

    def self.virtual_struct_type(g, concrete_gfuncs)
      concrete_infos = concrete_gfuncs.map(&.continuation_info)

      # We don't yet support the case where the public elements of the
      # continuation data do not match - they would need to be boxed/unboxed
      # in a wrapper virtual function, which we don't yet have code for.
      public_elements_match = concrete_infos
        .map(&.struct_element_types.[0...3].as(Array(LLVM::Type))).uniq.one?
      raise NotImplementedError.new \
        "heterogenous public members of virtual continuation types" \
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
        # 0xFFFF when the function is finished, or 0xFFFE if it errored.
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
        ctx.inventory[gfunc.link].each_yielding_call.each do |relate|
          cont_type = g.resolve_yielding_call_cont_type(relate, gfunc)

          # If this yielding function contains a recursive call to itself,
          # we won't know what struct size to allocate, and thus need to
          # make an indirection by turning this into a pointer element,
          # which can no longer be stack allocated and must be heap allocated.
          cont_type = cont_type.pointer \
            if CodeGen.recursively_contains_direct_struct_type?(cont_type, struct_type)

          list << cont_type
        end
        # And the yielding call receivers that go with each continuation.
        ctx.inventory[gfunc.link].each_yielding_call.each do |relate|
          list << g.llvm_type_of(relate.lhs, gfunc)
        end

        list
      end).not_nil!
    end

    def struct_gep_for_next_yield_index(cont : LLVM::Value)
      builder.struct_gep(cont, 0, "CONT.NEXT.GEP")
    end

    def struct_gep_for_local(cont : LLVM::Value, ref : Refer::Local)
      index = 3
      index += ctx.inventory[gfunc.link].each_local.index(ref).not_nil!

      builder.struct_gep(cont, index, "CONT.#{ref.name}.GEP")
    end

    def struct_gep_for_yielding_call_cont(cont : LLVM::Value, relate : AST::Relate)
      index = 3
      index += ctx.inventory[gfunc.link].local_count
      index += ctx.inventory[gfunc.link].each_yielding_call.index(relate).not_nil!

      member, _, _, _ = AST::Extract.call(relate)

      gep = builder.struct_gep(cont, index, "CONT.#{member.value}.NESTED.CONT.GEP")
      gep = builder.load(gep, gep.name) if gep.type.element_type.kind == LLVM::Type::Kind::Pointer
      gep
    end

    def struct_gep_for_yielding_call_receiver(cont : LLVM::Value, relate : AST::Relate)
      index = 3
      index += ctx.inventory[gfunc.link].local_count
      index += ctx.inventory[gfunc.link].each_yielding_call.size
      index += ctx.inventory[gfunc.link].each_yielding_call.index(relate).not_nil!

      member, _, _, _ = AST::Extract.call(relate)

      builder.struct_gep(cont, index, "CONT.#{member.value}.NESTED.RECEIVER.GEP")
    end

    def each_struct_index_for_yielding_call_conts
      index = 3
      index += ctx.inventory[gfunc.link].local_count;         from_index = index
      index += ctx.inventory[gfunc.link].yielding_call_count; upto_index = index

      from_index...upto_index
    end

    def get_next_yield_index(cont : LLVM::Value)
      next_yield_index_gep = struct_gep_for_next_yield_index(cont)
      builder.load(next_yield_index_gep, "CONT.NEXT")
    end

    def set_next_yield_index(cont : LLVM::Value, next_yield_index : Int32)
      raise "next_yield_index too high" if next_yield_index >= 0xFFFE

      builder.store(
        g.llvm.int16.const_int(next_yield_index),
        struct_gep_for_next_yield_index(cont),
      )
    end

    def set_as_error(cont : LLVM::Value)
      raise "this calling convention can't error" \
        unless gfunc.calling_convention.is_a?(GenFunc::YieldingErrorable)

      # Assign a value of 0xFFFE to the continuation's function pointer,
      # signifying the end of the call, with an error for the caller to raise.
      builder.store(
        g.llvm.int16.const_int(0xFFFE),
        struct_gep_for_next_yield_index(cont),
      )
    end

    def set_as_finished(cont : LLVM::Value)
      # Assign a value of 0xFFFF to the continuation's function pointer,
      # signifying the final end of the yielding call.
      builder.store(
        g.llvm.int16.const_int(0xFFFF),
        struct_gep_for_next_yield_index(cont),
      )
    end

    def check_is_error(cont : LLVM::Value)
      # Check if next_yield_index was set to the error value by set_as_error.
      builder.icmp(LLVM::IntPredicate::EQ,
        get_next_yield_index(cont),
        g.llvm.int16.const_int(0xFFFE),
      )
    end

    def check_is_finished(cont : LLVM::Value)
      case gfunc.calling_convention
      when GenFunc::Yielding
        # Check if next_yield_index was set to finished by set_as_finished.
        builder.icmp(LLVM::IntPredicate::EQ,
          get_next_yield_index(cont),
          g.llvm.int16.const_int(0xFFFF),
        )
      when GenFunc::YieldingErrorable
        # Check if next_yield_index was set to error or finished.
        builder.icmp(LLVM::IntPredicate::UGE,
          get_next_yield_index(cont),
          g.llvm.int16.const_int(0xFFFE),
        )
      else
        raise NotImplementedError.new("#{gfunc.calling_convention}")
      end
    end

    def struct_gep_for_final_return(cont : LLVM::Value)
      builder.struct_gep(cont, 1, "CONT.FINAL.GEP")
    end

    def get_final_return(cont : LLVM::Value)
      builder.load(struct_gep_for_final_return(cont), "CONT.FINAL")
    end

    def set_final_return(cont : LLVM::Value, value : LLVM::Value)
      builder.store(value, struct_gep_for_final_return(cont))
    end

    def struct_type_for_yield_out
      struct_element_types[2]
    end

    def struct_gep_for_yield_out(cont : LLVM::Value)
      builder.struct_gep(cont, 2, "CONT.YIELDOUT.GEP")
    end

    def get_yield_out(cont : LLVM::Value)
      builder.load(struct_gep_for_yield_out(cont), "CONT.YIELDOUT")
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
        each_struct_index_for_yielding_call_conts.each do |index|
          cont_type = struct_element_types[index]
          next unless cont_type.kind == LLVM::Type::Kind::Pointer

          # We have a recursive nested cont that we need to heap-allocate.
          builder.store(
            g.gen_alloc_struct(cont_type.element_type, "#{cont.name}.NEST.#{index}"),
            builder.struct_gep(cont, index, "#{cont.name}.NEST.#{index}.GEP"),
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
          cont_local = builder.bit_cast(
            gfunc.continuation_info.struct_gep_for_local(cont, ref),
            g.llvm_type_of(ref_defn).pointer,
          )
          builder.store(builder.load(cont_local, "#{ref.name}.RESTORED"), local)
        end
      end

      # Eagerly create struct geps for all yielding call continuations
      # and receivers that are nested in this yielding function func.
      ctx.inventory[gfunc.link].each_yielding_call.each do |relate|
        frame.yielding_call_conts[relate] = struct_gep_for_yielding_call_cont(cont, relate)
        frame.yielding_call_receivers[relate] = struct_gep_for_yielding_call_receiver(cont, relate)
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
      builder.position_at_end(invalid_block)
      builder.unreachable
    end
  end
end
