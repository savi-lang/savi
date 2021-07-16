##
# The purpose of the Privacy pass is to enforce the function privacy boundary.
# Functions whose identifier starts with an underscore are considered private,
# and can only be called from within the same library where they were defined.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps temporay state (on the stack) at the per-function level.
# This pass produces no output state.
#
class Savi::Compiler::Privacy
  def self.check_reified_func(ctx, infer : Infer::FuncAnalysis)
    infer.each_called_func_link(ctx) { |info, called_func_link|
      pos = info.pos

      # Only handle private calls (beginning with an underscore).
      return unless called_func_link.name.starts_with?("_")

      # PONY temporary workaround: for now, we don't enforce privacy in Pony
      # because we need to allow Pony's `builtin` to use our prelude library.
      # Remove this when Savi's prelude is a superset of Pony's `builtin`.
      return if pos.source.pony?

      # If the call site's library is the same as the function's library,
      # then there is no privacy issue and we can move on without error.
      next if pos.source.library.path == called_func_link.type.library.path

      # Otherwise we raise it as an error.
      Error.at pos, "This function call breaks privacy boundaries", [{
        called_func_link.resolve(ctx).ident.pos,
        "this is a private function from another library"
      }]
    }
  end

  class Pass < Compiler::Pass::Analyze(Nil, Nil, Nil)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil # no analysis output
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil # no analysis output
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Nil
      infer = ctx.infer[f_link]
      deps = infer
      prev = ctx.prev_ctx.try(&.privacy)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Privacy.check_reified_func(ctx, infer)

        nil # no analysis output
      end
    end
  end
end
