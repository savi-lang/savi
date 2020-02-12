##
# The purpose of the Lambda pass is to replace inline lambda forms with calls
# to new anonymous/hygienic types that represent the lambda as an external type.
#
# This pass mutates the Program topology.
# This pass mutates ASTs.
# This pass may raise a compilation error.
# This pass keeps temporary state at the per-function level.
# This pass produces no output state.
#
class Mare::Compiler::Lambda < Mare::AST::MutatingVisitor
  def self.run(ctx, library)
    library.types.each do |t|
      t.functions.each do |f|
        new(ctx, library, t, f).run
      end
    end
  end

  @ctx : Context
  @lib : Program::Library
  @type : Program::Type
  @func : Program::Function
  def initialize(@ctx, @lib, @type, @func)
    @last_num = 0
    @changed = false
    @observed_refs_stack = [] of Hash(Int32, AST::Identifier)
  end

  def run
    @func.params.try(&.accept(self))
    @func.ret.try(&.accept(self))
    @func.body.try(&.accept(self))
  end

  private def next_lambda_name
    "#{@type.ident.value}.#{@func.ident.value}.^#{@last_num += 1}"
  end

  def visit_pre(node : AST::Group)
    return node unless node.style == "^"

    @observed_refs_stack << Hash(Int32, AST::Identifier).new

    node
  end

  def visit(node : AST::Identifier)
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
  end

  def visit(node : AST::Group)
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
    @lib.types << lambda_type
    @ctx.namespace.add_lambda_type_later(@ctx, lambda_type, @lib)

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
  end
end
