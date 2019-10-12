lib LibLLVM
  fun get_entry_basic_block = LLVMGetEntryBasicBlock(function : ValueRef) : BasicBlockRef
  fun position_builder_before = LLVMPositionBuilderBefore(builder : BuilderRef, instruction : ValueRef)
  fun intptr_type_in_context = LLVMIntPtrTypeInContext(ContextRef, TargetDataRef) : TypeRef
  fun build_struct_gep = LLVMBuildStructGEP(builder : BuilderRef, pointer : ValueRef, index : UInt32, name : UInt8*) : ValueRef
  fun build_frem = LLVMBuildFRem(builder : BuilderRef, lhs : ValueRef, rhs : ValueRef, name : UInt8*) : ValueRef
  fun build_extract_value = LLVMBuildExtractValue(builder : BuilderRef, aggregate : ValueRef, index : UInt32, name : UInt8*) : ValueRef
  fun build_insert_value = LLVMBuildInsertValue(builder : BuilderRef, aggregate : ValueRef, element : ValueRef, index : UInt32, name : UInt8*) : ValueRef
  fun const_named_struct = LLVMConstNamedStruct(type : TypeRef, values : ValueRef*, num_values : UInt32) : ValueRef
  fun const_inbounds_gep = LLVMConstInBoundsGEP(value : ValueRef, indices : ValueRef*, num_indices : UInt32) : ValueRef
  fun const_bit_cast = LLVMConstBitCast(value : ValueRef, to_type : TypeRef) : ValueRef
  fun set_unnamed_addr = LLVMSetUnnamedAddr(global : ValueRef, is_unnamed_addr : Int32)
  fun is_unnamed_addr = LLVMIsUnnamedAddr(global : ValueRef) : Int32
  fun parse_bitcode_in_context = LLVMParseBitcodeInContext(context : ContextRef, mem_buf : MemoryBufferRef, out_m : ModuleRef*, out_message : UInt8**) : Int32
  fun link_modules = LLVMLinkModules2(dest : ModuleRef, src : ModuleRef) : Int32
  fun const_lshr = LLVMConstLShr(lhs : ValueRef, rhs : ValueRef) : ValueRef
  fun const_and = LLVMConstAnd(lhs : ValueRef, rhs : ValueRef) : ValueRef
  fun const_shl = LLVMConstShl(lhs : ValueRef, rhs : ValueRef) : ValueRef
end
