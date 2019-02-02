class LLVM::Builder
  def struct_gep(value, index, name = "")
    # check_value(value)

    Value.new LibLLVM.build_struct_gep(self, value, index.to_u32, name)
  end

  def frem(lhs, rhs, name = "")
    # check_value(lhs)
    # check_value(rhs)

    Value.new LibLLVM.build_frem(self, lhs, rhs, name)
  end
end
