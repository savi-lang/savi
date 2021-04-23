##
# The purpose of the Lambda pass is to replace inline lambda forms with calls
# to new anonymous/hygienic types that represent the lambda as an external type.
#
# This pass uses copy-on-mutate patterns to "mutate" the Program topology.
# This pass uses copy-on-mutate patterns to "mutate" the AST.
# This pass may raise a compilation error.
# This pass keeps temporary state at the per-function level.
# This pass produces no output state.
#
class Mare::Compiler::Lambda < Mare::AST::CopyOnMutateVisitor
  # TODO: Clean up, consolidate, and improve this caching mechanism.
  @@cache = {} of String => {UInt64, Program::Function}
  def self.cache_key(l, t, f)
    t.ident.value + "\0" + f.ident.value
  end
  def self.cached_or_run(l, t, f) : Program::Function
    input_hash = f.hash
    cache_key = cache_key(l, t, f)
    cache_result = @@cache[cache_key]?
    cached_hash, cached_func = cache_result if cache_result
    return cached_func if cached_func && cached_hash == input_hash

    yield

    .tap do |result|
      @@cache[cache_key] = {input_hash, result}
    end
  end

  def self.run(ctx, library)
    orig_library = library
    new_types = [] of Program::Type

    loop do
      library = library.types_map_cow do |t|
        t.functions_map_cow do |f|
          cached_or_run library, t, f do
            visitor = new(t, f)
            f = visitor.run(ctx)
            new_types.concat(visitor.new_types)
            f
          end
        end
      end

      break if new_types.empty?

      library = library.dup if library == orig_library
      new_types.each do |lambda_type|
        library.types << lambda_type
        ctx.namespace.add_lambda_type_later(ctx, lambda_type, library)
      end

      new_types.clear
    end

    library
  end

  getter new_types
  @type : Program::Type
  @func : Program::Function
  def initialize(@type, @func)
    @last_num = 0
    @changed = false
    @observed_refs_stack = [] of Hash(Int32, AST::Identifier)
    @new_types = [] of Program::Type
  end

  def run(ctx)
    f = @func

    params = f.params.try(&.accept(ctx, self))
    ret = f.ret.try(&.accept(ctx, self))
    body = f.body.try(&.accept(ctx, self))

    unless params.same?(f.params) && ret.same?(f.ret) && body.same?(f.body)
      f = f.dup
      f.params = params
      f.ret = ret
      f.body = body
    end
    f
  end

  private def next_lambda_name
    "#{@type.ident.value}.#{@func.ident.value}.^#{@last_num += 1}"
  end

  def visit_pre(ctx, node : AST::Group)
    return node unless node.style == "^"

    @observed_refs_stack << Hash(Int32, AST::Identifier).new

    node
  end

  def visit(ctx, node : AST::Identifier)
    return node unless node.value.starts_with?("^")

    Error.at node, "A lambda parameter can't be used outside of a lambda" \
      if @observed_refs_stack.empty?

    # Strip the "^" from the start of the identifier
    node.value = node.value[1..-1]

    # Save the identifier in the observed refs for this lambda, mapped by num.
    # If we see the same identifier more than once, don't overwrite.
    num = node.value.to_i32
    @observed_refs_stack.last[num] ||= node

    node
  rescue exc : Exception
    raise exc if exc.is_a?(Error) # TODO: ctx.errors multi-error capability
    raise Error.compiler_hole_at(node, exc)
  end

  def visit(ctx, node : AST::Group)
    return node unless node.style == "^"

    @changed = true
    name = next_lambda_name

    refs = @observed_refs_stack.pop
    unless refs.empty?
      param_count = refs.keys.max
      params = AST::Group.new("(").from(node)
      param_count.times.each do |i|
        params.terms << (refs[i + 1] || AST::Identifier.new("_").from(node))
      end
    end

    lambda_type_cap = AST::Identifier.new("non").from(node) # TODO: change this for stateful functions
    lambda_type_ident = AST::Identifier.new(name).from(node)
    lambda_type = Program::Type.new(lambda_type_cap, lambda_type_ident)
    lambda_type.add_tag(:hygienic)
    @new_types << lambda_type

    lambda_type.functions << Program::Function.new(
      AST::Identifier.new("non").from(node), # TODO: change this for stateful functions
      AST::Identifier.new("call").from(node),
      params,
      nil,
      node.dup.tap(&.style=(":")),
    )

    AST::Group.new("(").from(node).tap do |group|
      group.terms << AST::Identifier.new(name).from(node)
    end
  rescue exc : Exception
    raise exc if exc.is_a?(Error) # TODO: ctx.errors multi-error capability
    raise Error.compiler_hole_at(node, exc)
  end
end
