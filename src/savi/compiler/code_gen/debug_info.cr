class Savi::Compiler::CodeGen
  class DebugInfo
    # TODO: pick a real DWARF language ID
    LANGUAGE_ID = 0x000c # pretend to be C

    property! ctx : Context
    private getter! di_func : LibLLVMExt::Metadata

    def initialize(
      @llvm : LLVM::Context,
      @mod : LLVM::Module,
      @builder : LLVM::Builder,
      @target_data : LLVM::TargetData,
      @runtime : PonyRT | VeronaRT
    )
      @di = LLVM::DIBuilder.new(@mod)

      # TODO: real filename and dirname?
      filename = "(main)"
      dirname = ""

      @di.create_compile_unit(LANGUAGE_ID, filename, dirname, "Savi", false, "", 0)
    end

    def finish
      @di.end

      @mod.add_named_metadata_operand("llvm.module.flags", metadata([
        LLVM::ModuleFlag::Warning.value,
        "Debug Info Version",
        LLVM::DEBUG_METADATA_VERSION
      ])) if !ctx.options.no_debug
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

    def declare_local(pos, name, t : Reach::Ref, storage : LLVM::Value)
      declare_local_inner(pos, name, t, storage)
    end

    def declare_self_local(pos : Source::Pos, t : Reach::Ref, storage : LLVM::Value)
      name = "@"
      declare_local_inner(pos, name, t, storage)
    end

    def declare_local_inner(pos : Source::Pos, name : String, t : Reach::Ref, storage : LLVM::Value)
      file = di_file(pos.source)

      info = @di.create_auto_variable(
        @di_func.not_nil!,
        name,
        file,
        pos.row + 1,
        di_type(t, storage.type.element_type),
        0,
      )
      expr = @di.create_expression(nil, 0)

      @di.insert_declare_at_end(storage, info, expr, @builder.current_debug_location, @builder.insert_block.not_nil!)
    end

    def metadata(args)
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

    def di_file(source : Source)
      di_files = (@di_files ||= {} of String => LibLLVMExt::Metadata)
      di_files[source.path] ||=
        @di.create_file(File.basename(source.path), File.dirname(source.path))
    end

    def di_create_basic_type(
      t : Reach::Ref | String,
      llvm_type : LLVM::Type,
      dwarf_type : LLVM::DwarfTypeEncoding,
    )
      @di.create_basic_type(
        t.is_a?(Reach::Ref) ? t.show_type : t.to_s,
        @target_data.abi_size(llvm_type) * 8,
        @target_data.abi_alignment(llvm_type) * 8,
        dwarf_type,
      )
    end

    def di_create_pointer_type(
      name : String,
      element_di_type : LibLLVMExt::Metadata,
    )
      @di.create_pointer_type(
        element_di_type,
        @target_data.abi_size(@llvm.int8.pointer) * 8,
        @target_data.abi_alignment(@llvm.int8.pointer) * 8,
        name,
      )
    end

    @di_runtime_member_info : Hash(Int32, Tuple(String, LLVM::Type, LibLLVMExt::Metadata))?
    def di_runtime_member_info
      @di_runtime_member_info ||= begin
        @runtime.di_runtime_member_info(self)
          .as(Hash(Int32, Tuple(String, LLVM::Type, LibLLVMExt::Metadata)))
      end
    end

    def di_create_object_struct_pointer_type(
      t : Reach::Ref,
      llvm_type : LLVM::Type,
    )
      ident = t.single!.defn(ctx).ident
      name = ident.value

      # Create a temporary stand-in for this debug type, which is used to
      # prevent unwanted recursion if it (directly or indirectly) contains
      # this same debug type within one of its fields, which we visit below.
      tmp_debug_type = @di.create_replaceable_composite_type(nil, name, nil, 1, @llvm)
      @di_types.not_nil![t] = tmp_debug_type

      # Create the debug type, as a struct pointer to the struct type.
      debug_type = di_create_pointer_type(name,
        di_create_object_struct_type(t, llvm_type.element_type)
      )

      # Finally, replace the temporary stand-in we created above and return.
      @di.replace_temporary(tmp_debug_type, debug_type)
      debug_type
    end

    def di_create_object_struct_type(
      t : Reach::Ref,
      llvm_type : LLVM::Type,
    )
      ident = t.single!.defn(ctx).ident
      name = ident.value
      pos = ident.pos

      # First gather the debug type information for the type descriptor,
      # which is specific to the runtime we are using.
      di_member_info = Hash(Int32, Tuple(String, LLVM::Type, LibLLVMExt::Metadata)).new
      di_member_info.merge!(di_runtime_member_info)

      # Now add in the debug type information for the user fields struct.
      fields_struct_type = llvm_type.struct_element_types.last
      di_member_info[llvm_type.struct_element_types.size - 1] = {
        "FIELDS",
        fields_struct_type,
        di_create_fields_struct_type(t, fields_struct_type),
      }

      # Create the debug type, as a struct type with those element types.
      di_create_struct_type(name, llvm_type, di_member_info, pos)
    end

    def di_create_fields_struct_type(
      t : Reach::Ref,
      llvm_type : LLVM::Type,
    )
      reach_def = t.single_def!(ctx)
      ident = t.single!.defn(ctx).ident
      name = ident.value
      pos = ident.pos

      # Gather the debug type information for all user fields.
      di_member_info = Hash(Int32, Tuple(String, LLVM::Type, LibLLVMExt::Metadata)).new
      llvm_type.struct_element_types.each_with_index do |field_llvm_type, index|
        field_name, field_reach_ref = reach_def.fields[index]
        di_member_info[index] = {
          field_name,
          field_llvm_type,
          di_type(field_reach_ref, field_llvm_type),
        }
      end

      # Create the debug type, as a struct type with those element types.
      di_create_struct_type("#{name}.FIELDS", llvm_type, di_member_info, pos)
    end

    # This function is for cases where we are generating some internal struct
    # type with no Reach::Ref, so the caller must supply the info directly.
    def di_create_struct_type(
      name : String,
      llvm_type : LLVM::Type,
      member_infos : Hash(Int32, Tuple(String, LLVM::Type, LibLLVMExt::Metadata)),
      pos : Source::Pos? = nil
    )
      @di.create_struct_type(
        pos.try { |pos| di_file(pos.source) },
        name,
        pos.try { |pos| di_file(pos.source) },
        (pos.try(&.row) || 0) + 1,
        @target_data.abi_size(llvm_type) * 8,
        @target_data.abi_alignment(llvm_type) * 8,
        LLVM::DIFlags::Zero,
        nil,
        @di.get_or_create_type_array(
          member_infos.map do |index, (member_name, member_llvm_type, member_di_type)|
            @di.create_member_type(nil, member_name, nil, 1,
              @target_data.abi_size(member_llvm_type) * 8,
              @target_data.abi_alignment(member_llvm_type) * 8,
              @target_data.offset_of_element(llvm_type, index) * 8,
              LLVM::DIFlags::Zero,
              member_di_type,
            )
          end.compact
        )
      )
    end

    def di_create_enum_type(t : Reach::Ref, llvm_type : LLVM::Type)
      ident = t.single!.defn(ctx).ident
      name = ident.value
      pos = ident.pos
      underlying_type =
        if t.is_signed_numeric?(ctx)
          di_create_basic_type(t, llvm_type, LLVM::DwarfTypeEncoding::Signed)
        else
          di_create_basic_type(t, llvm_type, LLVM::DwarfTypeEncoding::Unsigned)
        end

      di_members = @di.get_or_create_array(
        t.find_enum_members!(ctx).map { |member|
          @di.create_enumerator(member.ident.value, member.value)
        }
      )

      @di.create_enumeration_type(
        pos.try { |pos| di_file(pos.source) },
        name,
        pos.try { |pos| di_file(pos.source) },
        (pos.try(&.row) || 0) + 1,
        @target_data.abi_size(llvm_type) * 8,
        @target_data.abi_alignment(llvm_type) * 8,
        di_members,
        underlying_type,
      )
    end

    def di_type(t : Reach::Ref, llvm_type : LLVM::Type)
      di_types = (@di_types ||= {} of Reach::Ref => LibLLVMExt::Metadata)
      di_types[t] ||=
        if t.is_enum?(ctx)
          di_create_enum_type(t, llvm_type)
        elsif t.is_floating_point_numeric?(ctx)
          di_create_basic_type(t, llvm_type, LLVM::DwarfTypeEncoding::Float)
        elsif t.is_signed_numeric?(ctx)
          di_create_basic_type(t, llvm_type, LLVM::DwarfTypeEncoding::Signed)
        elsif t.is_numeric?(ctx)
          di_create_basic_type(t, llvm_type, LLVM::DwarfTypeEncoding::Unsigned)
        elsif t.llvm_use_type(ctx) == :ptr
          di_create_pointer_type(
            t.show_type,
            di_type(
              t.single_def!(ctx).cpointer_type_arg(ctx),
              llvm_type.element_type,
            ),
          )
        elsif t.llvm_use_type(ctx) == :struct_value
          di_create_fields_struct_type(t, llvm_type)
        elsif t.llvm_use_type(ctx) == :struct_ptr
          di_create_object_struct_pointer_type(t, llvm_type)
        elsif t.llvm_use_type(ctx) == :struct_ptr_opaque
          # TODO: Some more descriptive debug type?
          di_create_basic_type(t, llvm_type, LLVM::DwarfTypeEncoding::Address)
        else
          raise NotImplementedError.new(t)
        end
    end

    # TODO: build a real type description here.
    def di_func_type(gfunc : GenFunc, file : LibLLVMExt::Metadata)
      # This is just a stub that pretends there is just one int parameter.
      int = @di.create_basic_type("int", 32, 32, LLVM::DwarfTypeEncoding::Signed)
      param_types = @di.get_or_create_type_array([int])
      @di.create_subroutine_type(file, param_types)
    end
  end
end
