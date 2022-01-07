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

extern "C" {

bool LLVMLinkForSaviDirectly(
  const char* Flavor,
  int ArgC, const char **ArgV
) {
  std::vector<const char *> Args(ArgV, ArgV + ArgC);

    for (auto it = Args.begin(); it != Args.end(); ++it) {
      errs() << *it << "\n";
    }


  // Invoke the linker.
  bool LinkResult = false;
  if (0 == strcmp(Flavor, "elf")) {
    LinkResult = lld::elf::link(Args, false, outs(), errs());
  } else if (0 == strcmp(Flavor, "mach_o")) {
    LinkResult = lld::macho::link(Args, false, outs(), errs());
  } else if (0 == strcmp(Flavor, "mingw")) {
    LinkResult = lld::mingw::link(Args, false, outs(), errs());
  } else if (0 == strcmp(Flavor, "coff")) {
    LinkResult = lld::coff::link(Args, false, outs(), errs());
  } else if (0 == strcmp(Flavor, "wasm")) {
    LinkResult = lld::wasm::link(Args, false, outs(), errs());
  } else {
    errs() << "Unsupported lld link flavor: " << Flavor;
  }

  // Show a helpful error message on failure.
  if (!LinkResult) {
    errs() << "Failed to link with lld, using these args:" << "\n";
    for (auto it = Args.begin(); it != Args.end(); ++it) {
      errs() << *it << "\n";
    }
  }

  return LinkResult;
}

bool LLVMLinkForSavi(
  const char* Flavor,
  const char* Target,
  int ArgC, const char **ArgV
) {
  // The arguments list for clang was given in a C-like FFI-friendly way, but
  // here we construct the C++-friendly equivalent of that args list.
  std::vector<const char *> Args(ArgV, ArgV + ArgC);

  // Create a libclang driver and compilation, using the given target and args.
  auto Diags = new clang::DiagnosticIDs();
  auto DiagOpts = new clang::DiagnosticOptions();
  auto DiagClient = new clang::TextDiagnosticPrinter(llvm::errs(), DiagOpts);
  clang::DiagnosticsEngine DiagEngine(Diags, DiagOpts, DiagClient);
  clang::driver::Driver Driver("clang", Target, DiagEngine);
  clang::driver::Compilation *Compilation = Driver.BuildCompilation(Args);

  // Iterate over the list of jobs in the compilation, expecting in practice
  // that this will only be a single job for linking, and that we can fulfill
  // the linking job using the embedded lld instead of an external linker.
  for (
    auto it = Compilation->getJobs().begin();
    it != Compilation->getJobs().end();
    ++it
  ) {
    // Ensure that the only job we're doing is linking, since we want to
    // avoid executing external shell commands, and only use embedded lld.
    if (it->getSource().getKind() != clang::driver::Action::LinkJobClass) {
      errs() << "Expected libclang to only need to link, but got this job:";
      it->Print(errs(), "\n", false);
      return false;
    }

    // Get the list of args that libclang says we should pass to the linker.
    auto LinkArgs = it->getArguments();

    // The lld library expects the first link argument to be the program name,
    // so we need to insert an extra "argument" here to fill that space.
    LinkArgs.insert(LinkArgs.begin(), "lld");

    // Invoke the linker, failing if the linker failed.
    if (!LLVMLinkForSaviDirectly(Flavor, LinkArgs.size(), LinkArgs.data()))
      return false;
  }

  return true;
}

}
