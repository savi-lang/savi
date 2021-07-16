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
class Savi::Compiler::Reparse < Savi::AST::CopyOnMutateVisitor
  # TODO: Clean up, consolidate, and improve this caching mechanism.
  @@cache = {} of Program::Function::Link => {UInt64, Program::Function}
  def self.cached_or_run(l, t, f : Program::Function) : Program::Function
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

  @@t_cache = {} of Program::Type::Link => {UInt64, Program::Type}
  def self.t_cached_or_run(l, t : Program::Type) : Program::Type
    t_link = t.make_link(l.make_link)
    input_hash = t.hash
    t_cache_result = @@t_cache[t_link]?
    t_cached_hash, t_cached_type = t_cache_result if t_cache_result
    return t_cached_type if t_cached_type && t_cached_hash == input_hash

    yield

    .tap do |result|
      @@t_cache[t_link] = {input_hash, result}
    end
  end

  @@ta_cache = {} of Program::TypeAlias::Link => {UInt64, Program::TypeAlias}
  def self.ta_cached_or_run(l, t : Program::TypeAlias) : Program::TypeAlias
    t_link = t.make_link(l.make_link)
    input_hash = t.hash
    ta_cache_result = @@ta_cache[t_link]?
    ta_cached_hash, ta_cached_type = ta_cache_result if ta_cache_result
    return ta_cached_type if ta_cached_type && ta_cached_hash == input_hash

    yield

    .tap do |result|
      @@ta_cache[t_link] = {input_hash, result}
    end
  end

  def self.run(ctx, library)
    visitor = new

    library = library.types_map_cow do |t|
      t = t_cached_or_run library, t do
        t = visitor.run_for_type_params(ctx, t)
      end

      t.functions_map_cow do |f|
        cached_or_run library, t, f do
          f = visitor.run(ctx, f)
        end
      end
    end

    library = library.aliases_map_cow do |t|
      ta_cached_or_run library, t do
        t = visitor.run_for_type_params(ctx, t)
      end
    end
  end

  def run_for_type_params(ctx, t)
    params = t.params
    return t unless params

    params = params.dup
    params.terms = params.terms.map do |param|
      visit_local_or_param_defn(ctx, param)
    end

    t = t.dup
    t.params = params
    t
  end

  def run(ctx, f)
    params = f.params
    ret = f.ret
    body = f.body

    # Visit parameters as if they are local definition sites.
    # Also, if any parameters contain assignments, convert them to defaults.
    if params
      params = params.dup if params.same?(f.params)
      params.terms = params.terms.map do |param|
        param = visit_local_or_param_defn(ctx, param)

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
    when "="
      visit_local_or_param_defn(ctx, node)
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

  def visit_local_or_param_defn(ctx, node)
    # For a local definition site, if it is defined as a 2-term whitespace group
    # turn the group into a type relation (assuming that it indicates the type)
    if node.is_a?(AST::Relate) \
    && (lhs = node.lhs).is_a?(AST::Group) \
    && lhs.style == " " && lhs.terms.size == 2
      group = lhs
      AST::Relate.new(
        AST::Relate.new(
          group.terms[0],
          AST::Operator.new("EXPLICITTYPE").from(group),
          group.terms[1],
        ).from(group),
        node.op,
        node.rhs,
      ).from(node)
    elsif node.is_a?(AST::Group) \
    && node.style == " " && node.terms.size == 2
      group = node
      AST::Relate.new(
        group.terms[0],
        AST::Operator.new("EXPLICITTYPE").from(group),
        group.terms[1],
      ).from(node)
    else
      node
    end
  end
end
