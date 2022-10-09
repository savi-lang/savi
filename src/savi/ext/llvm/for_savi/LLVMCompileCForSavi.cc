#include <llvm/IR/Module.h>
#include <clang/Basic/Diagnostic.h>
#include <clang/Basic/DiagnosticOptions.h>
#include <clang/Frontend/CompilerInstance.h>
#include <clang/Frontend/TextDiagnosticPrinter.h>
#include <clang/CodeGen/CodeGenAction.h>

///
// LLVMCompileCForSavi uses `clang` as a static library to embed a C compiler
// inside the Savi compiler, which we use to compile one or more accompanying
// C files into LLVM modules, which will be linked into the program and
// the functions defined in them will be callable from Savi via FFI.

using namespace llvm;

// A substitutable subclass of raw_ostream that captures its input to a string.
class LLVMCompileCForSaviCaptureOStream : public llvm::raw_ostream {
public:
  std::string Data;

  LLVMCompileCForSaviCaptureOStream() : raw_ostream(/*unbuffered=*/true), Data() {}

  void write_impl(const char *Ptr, size_t Size) override {
    Data.append(Ptr, Size);
  }

  uint64_t current_pos() const override { return Data.size(); }
};

extern "C" {

LLVMModuleRef LLVMCompileCForSavi(
  LLVMContextRef Context,
  bool IsDebug,
  int ArgC, const char **ArgV,
  const char** OutPtr, int* OutSize
) {
  std::vector<const char *> Args(ArgV, ArgV + ArgC);

  LLVMCompileCForSaviCaptureOStream Output;
  clang::DiagnosticsEngine DiagEngine(
    IntrusiveRefCntPtr<clang::DiagnosticIDs>(new clang::DiagnosticIDs),
    new clang::DiagnosticOptions,
    new clang::TextDiagnosticPrinter(
      Output,
      new clang::DiagnosticOptions()
    )
  );

  // Instantiate a compiler with the provided arguments.
  clang::CompilerInstance Compiler;
  clang::CompilerInvocation::CreateFromArgs(
    Compiler.getInvocation(),
    Args,
    DiagEngine
  );
  Compiler.createDiagnostics(
    new clang::TextDiagnosticPrinter(
      Output,
      new clang::DiagnosticOptions()
    ),
    false
  );

  Compiler.getInvocation().getCodeGenOpts().setDebugInfo(
    IsDebug ? clang::codegenoptions::FullDebugInfo : clang::codegenoptions::NoDebugInfo
  );

  // Compile (targetting an in-memory LLVM Module only).
  auto Action = std::make_unique<clang::EmitLLVMOnlyAction>(unwrap(Context));
  bool CompileResult = Compiler.ExecuteAction(*Action);

  // Show a helpful error message on failure.
  if (!CompileResult) {
    Output << "Failed to compile with embedded clang, using these args:\n";
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

  // Get the compiled LLVM Module, or NULL if the compilation failed.
  LLVMModuleRef Module =
    CompileResult ? wrap(Action->takeModule().release()) : NULL;

  return Module;
}

}
