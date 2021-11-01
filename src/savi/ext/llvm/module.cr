class LLVM::Module
  def add_named_metadata_operand(name : String, value : Value) : Nil
    LibLLVM.add_named_metadata_operand(self, name, value)
  end
end
