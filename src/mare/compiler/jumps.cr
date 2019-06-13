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
    Classify.always_error?(node)
    # TODO: early returns also jump away
  end
  
  def self.always_error?(node); Classify.always_error?(node) end
  def self.maybe_error?(node);  Classify.maybe_error?(node)  end
  def self.any_error?(node);    Classify.any_error?(node)    end
  
  def self.run(ctx)
    ctx.program.types.each do |t|
      t.functions.each do |f|
        new(f).run
      end
    end
  end
  
  getter func : Program::Function
  
  def initialize(@func)
  end
  
  def run
    func.ident.try(&.accept(self))
    func.params.try(&.accept(self))
    func.ret.try(&.accept(self))
    func.body.try(&.accept(self))
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
    if node.value == "error!"
      # An identifier is an always error if it is the special case of "error!".
      Classify.always_error!(node)
    elsif node.value[-1] == '!'
      # Otherwise, it is a maybe error if it ends in an exclamation point.
      Classify.maybe_error!(node)
    end
  end
  
  def touch(node : AST::Group)
    if node.terms.any? { |t| Classify.always_error?(t) }
      # A group is an always error if any term in it is.
      Classify.always_error!(node)
    elsif node.terms.any? { |t| Classify.maybe_error?(t) }
      # Otherwise, it is a maybe error if any term in it is.
      Classify.maybe_error!(node)
    end
  end
  
  def touch(node : AST::Prefix)
    if Classify.always_error?(node.term)
      # A prefixed term is an always error if its term is.
      Classify.always_error!(node)
    elsif Classify.maybe_error?(node.term)
      # Otherwise, it is a maybe error if its term is.
      Classify.maybe_error!(node)
    end
  end
  
  def touch(node : AST::Qualify)
    if Classify.always_error?(node.term) || Classify.always_error?(node.group)
      # A qualify is an always error if either its term or group is.
      Classify.always_error!(node)
    elsif Classify.maybe_error?(node.term) || Classify.maybe_error?(node.group)
      # Otherwise, it is a maybe error if either its term or group is.
      Classify.maybe_error!(node)
    end
  end
  
  def touch(node : AST::Relate)
    if Classify.always_error?(node.lhs) || Classify.always_error?(node.rhs)
      # A relation is an always error if either its left or right side is.
      Classify.always_error!(node)
    elsif Classify.maybe_error?(node.lhs) || Classify.maybe_error?(node.rhs)
      # Otherwise, it is a maybe error if either its left or right side is.
      Classify.maybe_error!(node)
    end
  end
  
  def touch(node : AST::Choice)
    # A choice is an always error only if all possible paths
    # through conds and bodies force us into an always error.
    some_possible_happy_path =
      node.list.size.times.each do |index|
        break false if Classify.always_error?(node.list[index][0])
        break true unless Classify.always_error?(node.list[index][1])
      end
    
    # A choice is a maybe error if any cond or body in it is a maybe error.
    some_possible_error_path =
      node.list.any? do |cond, body|
        Classify.any_error?(cond) || Classify.any_error?(body)
      end
    
    if !some_possible_happy_path
      Classify.always_error!(node)
    elsif some_possible_error_path
      Classify.maybe_error!(node)
    end
  end
  
  def touch(node : AST::Loop)
    if Classify.always_error?(node.cond) || (
      Classify.always_error?(node.body) && Classify.always_error?(node.else_body)
    )
      # A loop is an always error if the cond is an always error,
      # or if both the body and else body are always errors.
      Classify.always_error!(node)
    elsif Classify.maybe_error?(node.cond) \
    || Classify.any_error?(node.body) \
    || Classify.any_error?(node.else_body)
      # A loop is a maybe error if the cond is a maybe error,
      # or if either the body or else body are always errors or maybe errors.
      Classify.maybe_error!(node)
    end
  end
  
  def touch(node : AST::Try)
    if Classify.always_error?(node.body) && Classify.always_error?(node.else_body)
      # A try is an always error if both the body and else are always errors.
      Classify.always_error!(node)
    elsif Classify.any_error?(node.else_body)
      # A try is a maybe error if the else body has some chance to error.
      Classify.maybe_error!(node)
    end
  end
  
  def touch(node)
    # On all other nodes, do nothing.
  end
end
