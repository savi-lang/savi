struct LLVM::FunctionCollection
  def add(name, fun_type : LLVM::Type)
    # check_types_context(name, arg_types, ret_type)

    func = LibLLVM.add_function(@mod, name, fun_type)
    Function.new(func)
  end

  def add(name, fun_type : LLVM::Type)
    func = add(name, fun_type)
    yield func
    func
  end
end
