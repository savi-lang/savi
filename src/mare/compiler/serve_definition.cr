require "llvm"

##
# The purpose of the ServeHover pass is to serve up information about a given
# hover position in the source code, represented as a Source::Pos.
# When the [] method is called with a Source::Pos, it returns an Array(String)
# of messages describing the entity at that position, as well as an output
# Source::Pos value that points to the entirety of that entity's source.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass does not raise any compilation errors.
# This pass keeps no state other than holding onto the Context.
# This pass produces no output state.
#
class Mare::Compiler::ServeDefinition
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
    infer = ctx.infer.for_func_simple(ctx, f_link.type, f_link)

    describe_type = "type"

    begin
      infer_info = ctx.infer[f_link][node]?
      if infer_info.is_a? Infer::FromCall
        infer_info.follow_call_get_call_defns(ctx, infer).map do |_, _, other_f|
          next unless other_f
          other_f.ident.pos
        end.first
      else
        ref = refer[node]?
        case ref
        when Refer::Local, Refer::LocalUnion
          case ref
          when Refer::Local
            ref.defn.pos
          when Refer::LocalUnion
            ref.list.map do |local|
              local.defn.pos
            end.first
          end
        else
          inf = infer.analysis.resolved(ctx, node)
          inf.each_reachable_defn(ctx).map do |defn|
            defn.link.resolve(ctx).ident.pos
          end.first
        end
      end
    end
  end
end
