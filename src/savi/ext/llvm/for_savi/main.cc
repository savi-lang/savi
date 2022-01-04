// For convenience of compilation, we just use the C++ preprocessor to
// combine the following C++ files here into one file, as if they were headers.
//
// This implies we won't be able to have static naming collisions in them,
// but that's an acceptable limitation for us for now.
//
// Each C++ file defines a C function of the same name, which is meant to
// expose some LLVM-related functionality (which cannot be accomplished with
// the LLVM C API alone) in a C function that is FFI-callable from the compiler.
//
// That is, parts of the LLVM API are only exposed in C++ but not the C wrapper,
// so if we want to use them, we need to wrap them ourselves here.

#include "./LLVMLinkForSavi.cc"
#include "./LLVMOptimizeForSavi.cc"
#include "./LLVMRemapDIDirectoryForSavi.cc"
