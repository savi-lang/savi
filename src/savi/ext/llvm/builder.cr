class LLVM::Builder
  def clear_insertion_position
    LibLLVM.clear_insertion_position(self)
  end

  def insert_block
    ref = LibLLVM.get_insert_block(self)
    BasicBlock.new(ref) if ref
  end

  def position_before(instruction)
    LibLLVM.position_builder_before(self, instruction)
  end

  def frem(lhs, rhs, name = "")
    # check_value(lhs)
    # check_value(rhs)

    Value.new LibLLVM.build_frem(self, lhs, rhs, name)
  end

  def extract_value(aggregate, index, name = "")
    # check_value(aggregate)

    Value.new LibLLVM.build_extract_value(self, aggregate, index, name)
  end

  def insert_value(aggregate, element, index, name = "")
    # check_value(aggregate)
    # check_value(element)

    Value.new LibLLVM.build_insert_value(self, aggregate, element, index, name)
  end

  def ptr_to_int(value, to_type, name = "")
    Value.new LibLLVM.build_ptr2int(self, value, to_type, name)
  end

  def int_to_ptr(value, to_type, name = "")
    Value.new LibLLVM.build_int2ptr(self, value, to_type, name)
  end

  def is_null(value, name = "")
    Value.new LibLLVM.build_is_null(self, value, name)
  end

  def is_not_null(value, name = "")
    Value.new LibLLVM.build_is_not_null(self, value, name)
  end

  ##
  # Overrides related to opaque pointers (LLVM 15)

  def load(type : LLVM::Type, value : LLVM::Value, name = "")
    Value.new LibLLVM.build_load_2(self, type, value, name)
  end

  def struct_gep(type : LLVM::Type, value : LLVM::Value, index, name = "")
    Value.new LibLLVM.build_struct_gep_2(self, type, value, index.to_u32, name)
  end

  def inbounds_gep(type : LLVM::Type, value : LLVM::Value, index : LLVM::Value, name = "")
    indices = pointerof(index).as(LibLLVM::ValueRef*)
    Value.new LibLLVM.build_inbounds_gep_2(self, type, value, indices, 1, name)
  end

  def inbounds_gep(type : LLVM::Type, value : LLVM::Value, index1 : LLVM::Value, index2 : LLVM::Value, name = "")
    indices = uninitialized LLVM::Value[2]
    indices[0] = index1
    indices[1] = index2
    Value.new LibLLVM.build_inbounds_gep_2(self, type, value, indices.to_unsafe.as(LibLLVM::ValueRef*), 2, name)
  end

  def call(func_type : LLVM::Type, func, args : Array(LLVM::Value), name : String = "", bundle : LLVM::OperandBundleDef = LLVM::OperandBundleDef.null)
    Value.new LibLLVMExt.build_call2(self, func_type, func, (args.to_unsafe.as(LibLLVM::ValueRef*)), args.size, bundle, name)
  end

  def invoke(type : LLVM::Type, fn : LLVM::Function, args : Array(LLVM::Value), a_then, a_catch, bundle : LLVM::OperandBundleDef = LLVM::OperandBundleDef.null, name = "")
    Value.new LibLLVMExt.build_invoke2(self, type, fn, (args.to_unsafe.as(LibLLVM::ValueRef*)), args.size, a_then, a_catch, bundle, name)
  end
end
