class Mare::Compiler::CodeGen
  class DebugInfo
    # TODO: pick a real DWARF language ID
    LANGUAGE_ID = 0x000c # pretend to be C
    
    private getter! di_func : LibLLVMExt::Metadata
    
    def initialize(
      @llvm : LLVM::Context,
      @mod : LLVM::Module,
      @builder : LLVM::Builder,
    )
      @di = LLVM::DIBuilder.new(@mod)
      
      # TODO: real filename and dirname?
      filename = "(main)"
      dirname = ""
      
      @di.create_compile_unit(LANGUAGE_ID, filename, dirname, "Mare", false, "", 0)
    end
    
    def finish
      @di.end
      
      @mod.add_named_metadata_operand("llvm.module.flags", metadata([
        LLVM::ModuleFlag::Warning.value,
        "Debug Info Version",
        LLVM::DEBUG_METADATA_VERSION
      ]))
    end
    
    def func_start(gfunc : GenFunc, llvm_func : LLVM::Function)
      pos = gfunc.func.ident.pos
      name = llvm_func.name
      file = di_file(pos.source)
      
      @di_func =
        @di.create_function(file, name, name, file, pos.row + 1,
          di_func_type(gfunc, file), true, true, pos.row + 1,
          LLVM::DIFlags::Zero, false, llvm_func)
      
      set_loc(pos)
    end
    
    def func_end
      clear_loc
      
      @di_func = nil
    end
    
    def in_func?
      !!@di_func
    end
    
    def set_loc(node : AST::Node); set_loc(node.pos) end
    def set_loc(pos : Source::Pos)
      @builder.set_current_debug_location(pos.row + 1, pos.col + 1, di_func)
    end
    
    def clear_loc
      @builder.set_current_debug_location(0, 0, nil)
    end
    
    def declare_local(ref : Refer::Local, storage : LLVM::Value)
      pos = ref.defn.pos
      name = ref.name
      file = di_file(pos.source)
      
      # TODO: build a real type description here.
      # This is just a stub that pretends the variable is just an int.
      int = @di.create_basic_type("int", 32, 32, LLVM::DwarfTypeEncoding::Signed)
      
      info = @di.create_auto_variable(@di_func.not_nil!, name, file, pos.row + 1, int, 0)
      expr = @di.create_expression(nil, 0)
      
      @di.insert_declare_at_end(storage, info, expr, @builder.current_debug_location, @builder.insert_block)
    end
    
    private def metadata(args)
      values = args.map do |value|
        case value
        when String         then @llvm.md_string(value.to_s)
        when Symbol         then @llvm.md_string(value.to_s)
        when Number         then @llvm.int32.const_int(value)
        when Bool           then @llvm.int1.const_int(value ? 1 : 0)
        when LLVM::Value    then value
        when LLVM::Function then value.to_value
        when Nil            then LLVM::Value.null
        else raise NotImplementedError.new(value.class)
        end
      end
      @llvm.md_node(values)
    end
    
    private def di_file(source : Source)
      di_files = (@di_files ||= {} of String => LibLLVMExt::Metadata)
      di_files[source.path] ||=
        @di.create_file(File.basename(source.path), File.dirname(source.path))
    end
    
    # TODO: build a real type description here.
    private def di_func_type(gfunc : GenFunc, file : LibLLVMExt::Metadata)
      # This is just a stub that pretends there is just one int parameter.
      int = @di.create_basic_type("int", 32, 32, LLVM::DwarfTypeEncoding::Signed)
      param_types = @di.get_or_create_type_array([int])
      @di.create_subroutine_type(file, param_types)
    end
  end
end
