#include <clang/Driver/Driver.h>
#include <clang/Driver/Compilation.h>
#include <llvm/Support/VirtualFileSystem.h>

///
// LLVMDefaultClangFlagsForSavi uses `clang` as a static library to determine
// the correct C flags to pass to the embedded `clang` compiler later,
// including things like default header search paths, etc.

using namespace llvm;

extern "C" {

void LLVMDefaultClangFlagsForSavi(
  const char* Target, const char* Language,
  char*** OutArgsPtr, int* OutArgsCount
) {
  std::vector<const char *> Args;
  Args.push_back("clang");
  Args.push_back("-x"); Args.push_back(Language);
  Args.push_back("-"); // use stdin, to avoid naming an input file

  clang::DiagnosticsEngine DiagEngine(
    new clang::DiagnosticIDs,
    new clang::DiagnosticOptions
  );

  clang::driver::Driver Driver("clang", Target, DiagEngine);
  auto Compilation = Driver.BuildCompilation(Args);

  // Gather the system include directories as arguments.
  llvm::opt::ArgStringList OutArgs;
  Compilation->getDefaultToolChain().AddClangSystemIncludeArgs(
    Compilation->getArgs(),
    OutArgs
  );

  if (0 == strcmp(Language, "c++")) {
    OutArgs.push_back("-x");
    OutArgs.push_back("c++");
    OutArgs.push_back("-fexceptions");
    OutArgs.push_back("-fcxx-exceptions");
  }

  // Give the output args back to the caller, in a freshly allocated list,
  // containing a freshly allocated string for each output argument.
  // The caller will be responsible for freeing all of the allocations.
  if (OutArgsCount) *OutArgsCount = OutArgs.size();
  if (OutArgsPtr && OutArgs.size() > 0) {
    auto FreshCopy = (char**)malloc(OutArgs.size() * sizeof(char*));
    for (int i = 0; i < OutArgs.size(); i++) {
      if (strlen(OutArgs[i])) {
        FreshCopy[i] = (char*)malloc(strlen(OutArgs[i]) + 1);
        strcpy(FreshCopy[i], OutArgs[i]);
      } else {
        FreshCopy[i] = NULL;
      }
    }
    *OutArgsPtr = FreshCopy;
  }
}

}
