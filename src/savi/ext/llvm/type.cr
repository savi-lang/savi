struct LLVM::Type
  def const_struct(values : Array(Value))
    Value.new LibLLVM.const_named_struct(self,
      (values.to_unsafe.as(LibLLVM::ValueRef*)), values.size)
  end

  def struct_set_body(element_types : Array(LLVM::Type), packed = false)
    raise "Not a Struct" unless kind == Kind::Struct
    LibLLVM.struct_set_body(to_unsafe, (element_types.to_unsafe.as(LibLLVM::TypeRef*)), element_types.size, packed ? 1 : 0)
  end
end
