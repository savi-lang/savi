##
# The purpose of the Reparse pass is to clean up the work of the parser,
# such as rebalancing ASTs or converting them to more specific forms.
#
# For example, this pass converts dot-relations into function calls,
# a more specific AST form that is useful to handle as a single unit later.
#
# This pass also converts each dot-relation for a known nested type name
# into single identifier that represents the full type name, so that later
# passes do not need to deal with nested type names as if they were calls.
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
  def self.cached_or_run(ctx, l, t, f : Program::Function, deps) : Program::Function
    f_link = f.make_link(t.make_link(l.make_link))
    input_hash = {f, deps}.hash
    cache_result = @@cache[f_link]?
    cached_hash, cached_func = cache_result if cache_result
    return cached_func if cached_func && cached_hash == input_hash

    puts "    RERUN . #{self} #{f_link.show}" if cache_result && ctx.options.print_perf

    yield

    .tap do |result|
      @@cache[f_link] = {input_hash, result}
    end
  end

  @@t_cache = {} of Program::Type::Link => {UInt64, Program::Type}
  def self.t_cached_or_run(ctx, l, t : Program::Type, deps) : Program::Type
    t_link = t.make_link(l.make_link)
    input_hash = {t, deps}.hash
    t_cache_result = @@t_cache[t_link]?
    t_cached_hash, t_cached_type = t_cache_result if t_cache_result
    return t_cached_type if t_cached_type && t_cached_hash == input_hash

    puts "    RERUN . #{self} #{t_link.show}" if t_cache_result && ctx.options.print_perf

    yield

    .tap do |result|
      @@t_cache[t_link] = {input_hash, result}
    end
  end

  @@ta_cache = {} of Program::TypeAlias::Link => {UInt64, Program::TypeAlias}
  def self.ta_cached_or_run(ctx, l, t : Program::TypeAlias, deps) : Program::TypeAlias
    t_link = t.make_link(l.make_link)
    input_hash = {t, deps}.hash
    ta_cache_result = @@ta_cache[t_link]?
    ta_cached_hash, ta_cached_type = ta_cache_result if ta_cache_result
    return ta_cached_type if ta_cached_type && ta_cached_hash == input_hash

    puts "    RERUN . #{self} #{t_link.show}" if ta_cache_result && ctx.options.print_perf

    yield

    .tap do |result|
      @@ta_cache[t_link] = {input_hash, result}
    end
  end

  def self.run(ctx, package)
    package = package.types_map_cow do |t|
      t_namespace = ctx.namespace[t.ident.pos.source]
      t_deps = {t_namespace}

      t = t_cached_or_run ctx, package, t, t_deps do
        t = new(*t_deps).run_for_type_params(ctx, t)
      end

      t.functions_map_cow do |f|
        f_namespace = ctx.namespace[f.ident.pos.source]
        f_deps = {f_namespace}

        cached_or_run ctx, package, t, f, f_deps do
          f = new(*f_deps).run(ctx, f)
        end
      end
    end

    package = package.aliases_map_cow do |t|
      t_namespace = ctx.namespace[t.ident.pos.source]
      t_deps = {t_namespace}

      ta_cached_or_run ctx, package, t, t_deps do
        t = new(*t_deps).run_for_type_alias_target(ctx, t)
        t = new(*t_deps).run_for_type_params(ctx, t)
      end
    end
  end

  def initialize(@namespace : Namespace::Analysis)
  end

  def run_for_type_alias_target(ctx, t)
    target = t.target
    return t unless target

    orig_target = target
    target = target.accept(ctx, self)
    return t if target.same?(orig_target)

    t = t.dup
    t.target = target
    t
  end

  def run_for_type_params(ctx, t)
    params = t.params
    return t unless params

    params = params.dup
    params.terms = params.terms.map do |param|
      param = param.accept(ctx, self)
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
    else
      node
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

    node
  rescue exc : Exception
    raise Error.compiler_hole_at(node, exc)
  end

  def visit(ctx, node : AST::Relate)
    case node.op.value
    when "="
      visit_local_or_param_defn(ctx, node)
    when "."
      # Sometimes a dot relation can be converted into a nested type identifier.
      nested_ident = maybe_dot_relation_to_nested_type_ident(ctx, node)
      return nested_ident if nested_ident

      # Otherwise, it becomes a "call" node indicating a function call,
      # with the left side as the receiver and the right side as the name.
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

  def maybe_dot_relation_to_nested_type_ident(ctx, node : AST::Relate) : AST::Identifier?
    # See if it is possible to see this as a dot relation of identifiers,
    # digging through the layers to get the fully concatenated identifier.
    ident_value = maybe_nested_ident_value(node)
    return unless ident_value

    # If this nested identifier value exists as a type name in the namespace
    # for this source file, then convert this dot relation into an identifier.
    AST::Identifier.new(ident_value).from(node) if @namespace[ident_value]?
  end

  def maybe_nested_ident_value(node : AST::Node) : String?
    # If we're already looking at an identifier, return its value now.
    return node.value if node.is_a?(AST::Identifier?)

    # Otherwise, we'll only proceed if it is a dot relation.
    return unless node.is_a?(AST::Relate) && node.op.value == "."

    # And the right side must be an identifier.
    rhs = node.rhs
    return unless rhs.is_a?(AST::Identifier)

    # And the left side must be a possible nested identifier.
    lhs_value = maybe_nested_ident_value(node.lhs)
    return unless lhs_value

    # Concatenate the two sides like a nested identifier.
    "#{lhs_value}.#{rhs.value}"
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
