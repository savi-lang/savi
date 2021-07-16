require "llvm"

##
# The purpose of the ServeDefinition pass is to look up the definition position
# of a given entity specified by the cursor's incoming position.
# When the [] method is called with a Source::Pos, it returns an output
# Source::Pos value that points to the found definition of that entity's source.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps no state other than holding onto the Context.
# This pass produces no output state.
#
class Savi::Compiler::ServeDefinition
  getter! ctx : Context

  def run(ctx)
    @ctx = ctx
  end

  def [](pos : Source::Pos)
    Common::FindByPos.find(ctx, pos).try do |found|
      found.reverse_path.each do |node|
        f_link = found.f_link.not_nil! # TODO: accept non-function expressions

        other_pos = self[f_link, node]
        return other_pos unless other_pos.is_a? Nil
      end
    end
  end

  def [](f_link : Program::Function::Link, node : AST::Node)
    refer = ctx.refer[f_link]
    pre_infer = ctx.pre_infer[f_link]
    infer = ctx.infer[f_link]

    infer_info = pre_infer[node]?
    if infer_info.is_a? Infer::FromCall
      # Show first function definition site of a call.
      # TODO: Can we gracefully deal with cases of multiple possibilities?
      infer.each_called_func_link(ctx, for_info: infer_info) { |_, called_f_link|
        return called_f_link.resolve(ctx).ident.pos
      }
    else
      ref = refer[node]?
      case ref
      when Refer::Local
        # Show local variable definition site.
        ctx.local[f_link].any_initial_site_for(ref).pos
      else
        nil
      end
    end
  end
end
