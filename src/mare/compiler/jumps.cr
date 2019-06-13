##
# The purpose of the Jumps pass is to analyze control flow branches that jump
# away without giving a value. Such expressions have no value and no type,
# which is important to know in the Infer and CodeGen pass. This information
# is also used to analyze error handling completeness and partial functions.
#
# This pass does not mutate the Program topology.
# This pass sets flags on AST nodes but does not otherwise mutate ASTs.
# This pass does not raise any compilation errors.
# This pass keeps temporary state (on the stack) at the per-function level.
# This pass produces no output state.
#
class Mare::Compiler::Jumps < Mare::AST::Visitor
  def self.away?(node)
    Classify.error_jump?(node)
    # TODO: early returns also jump away
  end
  
  def self.run(ctx)
    ctx.program.types.each do |t|
      t.functions.each do |f|
        new(ctx, t, f).run
      end
    end
  end
  
  getter ctx : Context
  getter type : Program::Type
  getter func : Program::Function
  
  def initialize(@ctx, @type, @func)
  end
  
  def run
    func.params.try(&.accept(self))
    func.ret.try(&.accept(self))
    func.body.try(&.accept(self))
  end
  
  def refer
    ctx.refer[type][func]
  end
  
  # We don't deal with type expressions at all.
  def visit_children?(node)
    !Classify.type_expr?(node)
  end
  
  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node) unless Classify.type_expr?(node)
    node
  end
  
  def touch(node : AST::Identifier)
    # An identifier is an error jump if it ends in an exclamation point.
    Classify.error_jump!(node) if node.value[-1] == '!'
  end
  
  def touch(node : AST::Group)
    # A group is an error jump if any term in it is.
    Classify.error_jump!(node) \
      if node.terms.any? { |t| Classify.error_jump?(t) }
  end
  
  def touch(node : AST::Prefix)
    # A prefixed term is an error jump if its term is.
    Classify.error_jump!(node) \
      if Classify.error_jump?(node.term)
  end
  
  def touch(node : AST::Qualify)
    # A qualify is an error jump if either its term or group is.
    Classify.error_jump!(node) \
      if Classify.error_jump?(node.term) || Classify.error_jump?(node.group)
  end
  
  def touch(node : AST::Relate)
    # A relation is an error jump if either its left or right side is.
    Classify.error_jump!(node) \
      if Classify.error_jump?(node.lhs) || Classify.error_jump?(node.rhs)
  end
  
  def touch(node : AST::Choice)
    # A choice is an error jump only if all possible paths
    # through conds and bodies force us into an error jump.
    some_possible_happy_path =
      node.list.size.times.each do |index|
        break false if Classify.error_jump?(node.list[index][0])
        break true unless Classify.error_jump?(node.list[index][1])
      end
    
    Classify.error_jump!(node) unless some_possible_happy_path
  end
  
  def touch(node : AST::Loop)
    # A loop is an error jump if the cond is an error jump,
    # or if both the body and else body are error jumps.
    if Classify.error_jump?(node.cond) \
    || (Classify.error_jump?(node.body) && Classify.error_jump?(node.else_body))
      Classify.error_jump!(node)
    end
  end
  
  def touch(node : AST::Try)
    # A try is an error jump if both the body and else body are error jumps.
    if Classify.error_jump?(node.body) && Classify.error_jump?(node.else_body)
      Classify.error_jump!(node)
    end
  end
  
  def touch(node)
    # On all other nodes, do nothing.
  end
end
