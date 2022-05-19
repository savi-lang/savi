module LLVM::ValueMethods
  def unnamed_addr=(unnamed_addr)
    LibLLVM.set_unnamed_addr(self, unnamed_addr ? 1 : 0)
  end

  def unnamed_addr?
    LibLLVM.is_unnamed_addr(self) != 0
  end

  def dll_storage_class : LLVM::DLLStorageClass
    LibLLVM.get_dll_storage_class(self)
  end

  def dll_storage_class=(cls : LLVM::DLLStorageClass)
    LibLLVM.set_dll_storage_class(self, cls)
    cls
  end

  def to_value
    Value.new to_unsafe
  end
end
