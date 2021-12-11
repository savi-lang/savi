##
# The purpose of the Load pass is to load more manifests packages into memory,
# based on the dependency declarations found in the selected root manifest.
#
# This pass does not mutate the Program topology directly, though it instructs Context to compile more packages.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps no state.
# This pass produces no output state.
#
class Savi::Compiler::Load
  def initialize
  end

  def run(ctx)
    return if ctx.options.skip_manifest

    loaded = Set(Packaging::Manifest).new
    ctx.manifests.manifests_by_name.each_value { |manifest|
      next if loaded.includes?(manifest)
      loaded.add(manifest)

      ctx.compile_package(manifest)
    }
  end
end
