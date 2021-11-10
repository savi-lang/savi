lib LibC
  # LLVM_CLANG_C_BUILDSYSTEM_H = 
  fun clang_getBuildSessionTimestamp() : ULongLong
  type CXVirtualFileOverlayImpl = Void
  alias CXVirtualFileOverlay = CXVirtualFileOverlayImpl*
  fun clang_VirtualFileOverlay_create(UInt) : CXVirtualFileOverlay
  fun clang_VirtualFileOverlay_addFileMapping(CXVirtualFileOverlay, Char*, Char*) : CXErrorCode
  fun clang_VirtualFileOverlay_setCaseSensitivity(CXVirtualFileOverlay, Int) : CXErrorCode
  fun clang_VirtualFileOverlay_writeToBuffer(CXVirtualFileOverlay, UInt, Char**, UInt*) : CXErrorCode
  fun clang_free(Void*) : Void
  fun clang_VirtualFileOverlay_dispose(CXVirtualFileOverlay) : Void
  type CXModuleMapDescriptorImpl = Void
  alias CXModuleMapDescriptor = CXModuleMapDescriptorImpl*
  fun clang_ModuleMapDescriptor_create(UInt) : CXModuleMapDescriptor
  fun clang_ModuleMapDescriptor_setFrameworkModuleName(CXModuleMapDescriptor, Char*) : CXErrorCode
  fun clang_ModuleMapDescriptor_setUmbrellaHeader(CXModuleMapDescriptor, Char*) : CXErrorCode
  fun clang_ModuleMapDescriptor_writeToBuffer(CXModuleMapDescriptor, UInt, Char**, UInt*) : CXErrorCode
  fun clang_ModuleMapDescriptor_dispose(CXModuleMapDescriptor) : Void
end
