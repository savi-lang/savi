struct LLVM::BasicBlock
  def get_terminator
    ref = LibLLVM.get_basic_block_terminator(to_unsafe)
    Value.new(ref) if ref
  end
end
