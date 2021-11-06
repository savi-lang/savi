lib LibC
  # LLVM_CLANG_C_CXERRORCODE_H = 
  enum CXErrorCode : UInt
    Success = 0
    Failure = 1
    Crashed = 2
    InvalidArguments = 3
    ASTReadError = 4
  end
end
