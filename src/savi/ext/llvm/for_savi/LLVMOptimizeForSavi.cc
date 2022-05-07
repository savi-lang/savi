#include <llvm/Analysis/AliasAnalysis.h>
#include <llvm/Passes/PassBuilder.h>

///
// LLVMOptimizeForSavi runs standard (and in the future, also Savi-specific)
// LLVM passes on the given module, to optimize it. A boolean parameter allows
// the caller to specify whether full or minimum optimization is desired.

using namespace llvm;

extern "C" {

void LLVMOptimizeForSavi(LLVMModuleRef ModRef, LLVMBool WantsFullOptimization) {
  // Most of this is the standard ceremony for running standard LLVM passes.
  // See <https://llvm.org/docs/NewPassManager.html> for details.

  PassBuilder PB;
  LoopAnalysisManager LAM;
  FunctionAnalysisManager FAM;
  CGSCCAnalysisManager CGAM;
  ModuleAnalysisManager MAM;

  // Enable the default alias analysis pipeline.
  FAM.registerPass([&] { return PB.buildDefaultAAPipeline(); });

  // Wire in all of the analysis managers.
  PB.registerModuleAnalyses(MAM);
  PB.registerCGSCCAnalyses(CGAM);
  PB.registerFunctionAnalyses(FAM);
  PB.registerLoopAnalyses(LAM);
  PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);

  // Create the top-level module pass manager using the default LLVM pipeline.
  // Respect the parameter that either requests or declines full optimization.
  ModulePassManager MPM = PB.buildPerModuleDefaultPipeline(
    WantsFullOptimization ? OptimizationLevel::O3 : OptimizationLevel::O0
  );
  MPM.run(*unwrap(ModRef), MAM);
}

}
