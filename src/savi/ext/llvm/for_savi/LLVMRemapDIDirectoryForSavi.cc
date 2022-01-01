#include <llvm/IR/DebugInfo.h>
#include <llvm/IR/DIBuilder.h>
#include <llvm/Passes/PassBuilder.h>

///
// LLVMRemapDIDirectoryForSavi modifies the debug information for a module.
// Specifically, for each DIFile whose Directory is the given BeforeDirectory,
// it will replace that Directory with the given AfterDirectory string.

using namespace llvm;

class RemapDIDirectoryPass : public PassInfoMixin<RemapDIDirectoryPass> {
  StringRef BeforeDirectory;
  StringRef AfterDirectory;

public:
  RemapDIDirectoryPass(StringRef BeforeDirectory, StringRef AfterDirectory)
    : BeforeDirectory(BeforeDirectory), AfterDirectory(AfterDirectory) {}

  PreservedAnalyses run(Module &M, ModuleAnalysisManager &AM) {
    DIBuilder DI(M);
    DebugInfoFinder Finder;

    // Iterate over all DIScopes in the Module.
    Finder.processModule(M);
    auto DIScopes = Finder.scopes();
    for (auto it = DIScopes.begin(); it != DIScopes.end(); ++it) {
      DIFile* File = (*it)->getFile();
      if (!File) continue;

      // Skip this DIFile if it doesn't match the BeforeDirectory.
      if (!File->getDirectory().equals(BeforeDirectory)) continue;

      // Replace the Directory (index 1) of the DIFile with the AfterDirectory.
      File->replaceOperandWith(1, MDString::get(M.getContext(), AfterDirectory));
    }

    return PreservedAnalyses::all();
  }
};

extern "C" {

void LLVMRemapDIDirectoryForSavi(
  LLVMModuleRef ModRef,
  const char* BeforeDirectory,
  const char* AfterDirectory
) {
  PassBuilder PB;
  ModuleAnalysisManager MAM;
  PB.registerModuleAnalyses(MAM);

  ModulePassManager MPM;
  MPM.addPass(
    RemapDIDirectoryPass(StringRef(BeforeDirectory), StringRef(AfterDirectory))
  );
  MPM.run(*unwrap(ModRef), MAM);
}

}
