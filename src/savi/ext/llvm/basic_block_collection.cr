require "./basic_block"

struct LLVM::BasicBlockCollection
  def empty?
    !LibLLVM.get_first_basic_block(@function)
  end
end
