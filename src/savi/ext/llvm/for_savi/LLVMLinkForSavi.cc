#include <clang/Driver/Compilation.h>
#include <clang/Driver/Driver.h>
#include <clang/Frontend/TextDiagnosticPrinter.h>
#include <lld/Common/Driver.h>
#include <llvm/Support/InitLLVM.h>
#include <llvm/Support/Process.h>
#include <llvm/Support/VirtualFileSystem.h>

///
// LLVMLinkForSavi uses `lld` as a static library to embed a linker within the
// Savi compiler, so that we can create executable programs without relying
// on an external linker program as a (varying and hard to control) dependency.

using namespace llvm;

// A substitutable subclass of raw_ostream that captures its input to a string.
class LLVMLinkForSaviCaptureOStream : public llvm::raw_ostream {
public:
  std::string Data;

  LLVMLinkForSaviCaptureOStream() : raw_ostream(/*unbuffered=*/true), Data() {}

  void write_impl(const char *Ptr, size_t Size) override {
    Data.append(Ptr, Size);
  }

  uint64_t current_pos() const override { return Data.size(); }
};

extern "C" {

bool LLVMLinkForSavi(
  const char* Flavor,
  int ArgC, const char **ArgV,
  const char** OutPtr, int* OutSize
) {
  std::vector<const char *> Args(ArgV, ArgV + ArgC);

  // Create an output stream that captures the stdout/stderr info to a string.
  LLVMLinkForSaviCaptureOStream Output;

  // Invoke the linker.
  bool LinkResult = false;
  if (0 == strcmp(Flavor, "elf")) {
    LinkResult = lld::elf::link(Args, Output, Output, false, false);
  } else if (0 == strcmp(Flavor, "mach_o")) {
    LinkResult = lld::macho::link(Args, Output, Output, false, false);
  } else if (0 == strcmp(Flavor, "mingw")) {
    LinkResult = lld::mingw::link(Args, Output, Output, false, false);
  } else if (0 == strcmp(Flavor, "coff")) {
    LinkResult = lld::coff::link(Args, Output, Output, false, false);
  } else if (0 == strcmp(Flavor, "wasm")) {
    LinkResult = lld::wasm::link(Args, Output, Output, false, false);
  } else {
    Output << "Unsupported lld link flavor: " << Flavor;
  }

  // Show a helpful error message on failure.
  if (!LinkResult) {
    Output << "Failed to link with embedded lld, using these args:";
    for (auto it = Args.begin(); it != Args.end(); ++it) {
      Output << *it << "\n";
    }
  }

  // Give the printed output back to the caller, in a fresh allocation.
  // The caller will be responsible for freeing the allocation.
  if (OutSize) *OutSize = Output.Data.size();
  if (OutPtr) {
    auto FreshCopy = (char*)malloc(Output.Data.size());
    strncpy(FreshCopy, Output.Data.data(), Output.Data.size());
    *OutPtr = FreshCopy;
  }

  return LinkResult;
}

}
