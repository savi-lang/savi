class LLVM::Builder
  def position_before(instruction)
    LibLLVM.position_builder_before(self, instruction)
  end

  def struct_gep(value, index, name = "")
    # check_value(value)

    Value.new LibLLVM.build_struct_gep(self, value, index.to_u32, name)
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
end
