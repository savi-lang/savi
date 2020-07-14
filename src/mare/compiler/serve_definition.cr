require "llvm"
require "debug"

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

  def initialize
  end

  def run(ctx)
    @ctx = ctx
  end

  private def find(pos : Source::Pos, within : AST::Node)
    # TODO: Use the visitor pattern instead?
    case within
    when AST::Prefix
      [within.op, within.term].each do |term|
        return [within] + find(pos, term) if term.span_pos.contains?(pos)
      end
    when AST::Qualify
      [within.term, within.group].each do |term|
        return [within] + find(pos, term) if term.span_pos.contains?(pos)
      end
    when AST::Group
      within.terms.each do |term|
        return [within] + find(pos, term) if term.span_pos.contains?(pos)
      end
    when AST::Relate
      [within.lhs, within.op, within.rhs].each do |term|
        return [within] + find(pos, term) if term.span_pos.contains?(pos)
      end
    when AST::FieldWrite
      [within.rhs].each do |term|
        return [within] + find(pos, term) if term.span_pos.contains?(pos)
      end
    when AST::FieldReplace
      [within.rhs].each do |term|
        return [within] + find(pos, term) if term.span_pos.contains?(pos)
      end
    when AST::Choice
      within.list.each do |cond, body|
        return [within] + find(pos, cond) if cond.span_pos.contains?(pos)
        return [within] + find(pos, body) if body.span_pos.contains?(pos)
      end
    when AST::Loop
      [within.cond, within.body, within.else_body].each do |term|
        return [within] + find(pos, term) if term.span_pos.contains?(pos)
      end
    when AST::Try
      [within.body, within.else_body].each do |term|
        return [within] + find(pos, term) if term.span_pos.contains?(pos)
      end
    end
    [within]
  end

  def [](pos : Source::Pos)
    ctx.program.libraries.each do |library|
      library.types.each do |t|
        next unless t.ident.pos.source == pos.source

        t.functions.each do |f|
          next unless f.ident.pos.source == pos.source

          f.body.try do |body|
            if body.pos.contains?(pos)
              find(pos, body).reverse_each do |node|

                t_link = t.make_link(library)
                f_link = f.make_link(t_link)

                other_pos = self[t_link, f_link, node]
                return other_pos unless other_pos.is_a? Nil
              end
            end
          end
        end
      end
    end

    nil
  end

  def [](t_link : Program::Type::Link, f_link : Program::Function::Link, node : AST::Node)
    refer = ctx.refer[f_link]

    infer = ctx.infer.for_func_simple(ctx, t_link, f_link)

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
          inf.each_reachable_defn.map do |defn|
            defn.link.resolve(ctx).ident.pos
          end.first
        end
      end
    end
  end
end
