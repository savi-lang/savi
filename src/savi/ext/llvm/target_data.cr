struct LLVM::TargetData
  def big_endian?
    LibLLVM.byte_order(self) == LibLLVM::ByteOrdering::BigEndian
  end

  def little_endian?
    LibLLVM.byte_order(self) == LibLLVM::ByteOrdering::LittleEndian
  end
end
