##
# The purpose of the Reparse pass is to clean up the work of the parser,
# such as rebalancing ASTs or converting them to more specific forms.
#
# This pass uses copy-on-mutate patterns to "mutate" the Program topology.
# This pass uses copy-on-mutate patterns to "mutate" the AST.
# This pass may raise compilation errors.
# This pass keeps temporary state at the per-function level.
# This pass produces no output state.
#
class Mare::Compiler::Reparse < Mare::AST::CopyOnMutateVisitor
  # TODO: Clean up, consolidate, and improve this caching mechanism.
  @@cache = {} of Program::Function::Link => {UInt64, Program::Function}
  def self.cached_or_run(l, t, f) : Program::Function
    f_link = f.make_link(t.make_link(l.make_link))
    input_hash = f.hash
    cache_result = @@cache[f_link]?
    cached_hash, cached_func = cache_result if cache_result
    return cached_func if cached_func && cached_hash == input_hash

    yield

    .tap do |result|
      @@cache[f_link] = {input_hash, result}
    end
  end

  def self.run(ctx, library)
    library.types_map_cow do |t|
      t.functions_map_cow do |f|
        cached_or_run library, t, f do
          f = new.run(ctx, f)
        end
      end
    end
  end

  def run(ctx, f)
    params = f.params
    ret = f.ret
    body = f.body

    # If any parameters contain assignments, convert them to defaults.
    if body && params
      params = params.dup if params.same?(f.params)
      params.terms = params.terms.map do |param|
        next param unless param.is_a?(AST::Relate) && param.op.value == "="

        AST::Relate.new(
          param.lhs,
          AST::Operator.new("DEFAULTPARAM").from(param.op),
          param.rhs,
        ).from(param)
      end
    end

    # Visit the parameter signature and return type.
    params = params.try(&.accept(ctx, self))
    ret = ret.try(&.accept(ctx, self))
    body = body.try(&.accept(ctx, self))

    unless params.same?(f.params) && ret.same?(f.ret) && body.same?(f.body)
      f = f.dup
      f.params = params
      f.ret = ret
      f.body = body
    end
    f
  end

  def visit(ctx, node : AST::Identifier)
    if node.value == "@"
      node
    elsif node.value.char_at(0) == '@'
      receiver_pos = node.pos.subset(0, node.pos.size - 1)
      ident_pos = node.pos.subset(1, 0)
      receiver = AST::Identifier.new("@").with_pos(receiver_pos)
      ident = AST::Identifier.new(node.value[1..-1]).with_pos(ident_pos)
      AST::Call.new(receiver, ident).from(node)
    elsif node.pos.source.pony?
      # PONY special case: uses the keyword `this` for the self value.
      if node.value == "this"
        AST::Identifier.new("@").from(node)
      # PONY special case: uses the keyword `error` for the error statement.
      elsif node.value == "error"
        AST::Jump.new(AST::Identifier.new("None").from(node), AST::Jump::Kind::Error).from(node)
      else
        node
      end
    else
      node
    end
  rescue exc : Exception
    raise Error.compiler_hole_at(node, exc)
  end

  # PONY special case: many operators have different names in Pony.
  def visit(ctx, node : AST::Operator)
    return node unless node.pos.source.pony?

    case node.value
    when "consume" then AST::Operator.new("--").from(node)
    when "and"     then AST::Operator.new("&&").from(node)
    when "or"      then AST::Operator.new("||").from(node)
    else node
    end
  rescue exc : Exception
    raise Error.compiler_hole_at(node, exc)
  end

  def visit(ctx, node : AST::Qualify)
    return node unless node.group.style == "(" || node.group.style == "(!"

    term = node.term
    return node unless term.is_a?(AST::Call)

    # Move the qualification group into call args.
    args = node.group
    annotations = node.annotations
    node = AST::Call.new(
      term.receiver,
      term.ident,
      args,
    ).from(term)
    node.annotations = annotations

    # PONY special case: exclamation from args gets moved to the ident.
    if node.pos.source.pony? && args.style == "(!"
      new_ident_value = "#{node.ident.value}!"
      node.ident = AST::Identifier.new(new_ident_value).from(node.ident)
      args.style = "("
    end

    node
  rescue exc : Exception
    raise Error.compiler_hole_at(node, exc)
  end

  def visit(ctx, node : AST::Relate)
    case node.op.value
    when "'", " ", "<:", "!<:", "===", "!==", "DEFAULTPARAM"
      node # skip these special-case operators
    when "."
      visit(ctx,
        AST::Call.new(node.lhs, node.rhs.as(AST::Identifier)).from(node)
      )
    when "->"
      return node unless (call = node.lhs).is_a?(AST::Call)

      yield_params = nil
      yield_block = nil
      if (rhs = node.rhs).is_a?(AST::Group)
        if rhs.style == "("
          yield_block = rhs
        elsif rhs.style == "|" && rhs.terms.size == 2
          yield_params = rhs.terms.first.as(AST::Group)
          yield_block = rhs.terms.last.as(AST::Group)
        else
          ctx.error_at node.rhs, "This is invalid syntax for a yield block"
        end
      else
        ctx.error_at node.rhs, "This is invalid syntax for a yield block"
      end

      visit(ctx,
        AST::Call.new(
          call.receiver,
          call.ident,
          call.args,
          yield_params,
          yield_block,
        ).from(node)
      )
    else
      node
    end
  rescue exc : Exception
    raise Error.compiler_hole_at(node, exc)
  end
end
