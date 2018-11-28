class LLVM::Builder
  def struct_gep(value, index, name = "")
    # check_value(value)

    Value.new LibLLVM.build_struct_gep(self, value, index.to_u32, name)
  end
end
