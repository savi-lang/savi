struct LLVM::Type
  def const_struct(values : Array(Value))
    Value.new LibLLVM.const_named_struct(self,
      (values.to_unsafe.as(LibLLVM::ValueRef*)), values.size)
  end
end
