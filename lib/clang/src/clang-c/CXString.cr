lib LibC
  # LLVM_CLANG_C_CXSTRING_H = 
  struct CXString
    data : Void*
    private_flags : UInt
  end
  struct CXStringSet
    strings : CXString*
    count : UInt
  end
  fun clang_getCString(CXString) : Char*
  fun clang_disposeString(CXString) : Void
  fun clang_disposeStringSet(CXStringSet*) : Void
end
