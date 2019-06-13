##
# The purpose of the Classify pass is to do some further semantic parsing of
# AST forms to add additional context about what those forms mean, in the form
# of flag bits being set on the state of the AST nodes themselves.
#
# This pass does not mutate the Program topology.
# This pass sets flags on AST nodes but does not otherwise mutate ASTs.
# This pass does not raise any compilation errors.
# This pass keeps temporary state (on the stack) at the per-function level.
# This pass produces no output state.
#
class Mare::Compiler::Classify < Mare::AST::Visitor
  FLAG_VALUE_NOT_NEEDED  = 0x1_u64 # set here in the Classify pass
  FLAG_TYPE_EXPR         = 0x2_u64 # set here in the Classify pass
  FLAG_FURTHER_QUALIFIED = 0x4_u64 # set here in the Classify pass
  FLAG_ERROR_JUMP        = 0x8_u64 # set in the Jumps pass
  
  def self.value_not_needed?(node); (node.flags & FLAG_VALUE_NOT_NEEDED) != 0 end
  def self.value_needed?(node);     (node.flags & FLAG_VALUE_NOT_NEEDED) == 0 end
  def self.value_not_needed!(node); node.flags |= FLAG_VALUE_NOT_NEEDED end
  def self.value_needed!(node);     node.flags &= ~FLAG_VALUE_NOT_NEEDED end
  
  def self.type_expr?(node); (node.flags & FLAG_TYPE_EXPR) != 0 end
  def self.type_expr!(node); node.flags |= FLAG_TYPE_EXPR end
  
  def self.further_qualified?(node); (node.flags & FLAG_FURTHER_QUALIFIED) != 0 end
  def self.further_qualified!(node); node.flags |= FLAG_FURTHER_QUALIFIED end
  
  def self.error_jump?(node); (node.flags & FLAG_ERROR_JUMP) != 0 end
  def self.error_jump!(node); node.flags |= FLAG_ERROR_JUMP end
  
  # This visitor marks the given node tree as being a type_expr.
  class TypeExprVisitor < Mare::AST::Visitor
    INSTANCE = new
    def self.instance; INSTANCE end
    
    def visit(node)
      Classify.type_expr!(node)
      node
    end
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
    func.ret.try(&.accept(TypeExprVisitor.instance))
    func.body.try(&.accept(self))
  end
  
  def refer
    ctx.refer[type][func]
  end
  
  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(node)
    touch(node)
    node
  end
  
  # An Operator can never have a value, so its value should never be needed.
  def touch(op : AST::Operator)
    Classify.value_not_needed!(op)
  end
  
  def touch(group : AST::Group)
    case group.style
    when "(", ":"
      # In a sequence-style group, only the value of the final term is needed.
      group.terms.each { |t| Classify.value_not_needed!(t) }
      Classify.value_needed!(group.terms.last) unless group.terms.empty?
    when " "
      if group.terms.size == 2
        # Treat this as an explicit type qualification, such as in the case
        # of a local assignment with an explicit type. The value isn't used.
        group.terms[1].accept(TypeExprVisitor.instance)
      else
        raise NotImplementedError.new(group.to_a.inspect)
      end
    end
  end
  
  def touch(qualify : AST::Qualify)
    # In a Qualify, we mark the term as being in such a qualify.
    Classify.further_qualified!(qualify.term)
    
    case refer[qualify.term]
    when Refer::Unresolved
      # We assume this qualify to be a function call with arguments.
      # All of the arguments will have their value used, despite any earlier
      # work we did of marking them all as unused due to being in a Group.
      qualify.group.terms.each { |t| Classify.value_needed!(t) }
    when Refer::Type, Refer::TypeAlias, Refer::TypeParam
      # We assume this qualify to be type with type arguments.
      # None of the arguments will have their value used,
      # and they are all type expressions.
      qualify.group.terms.each do |t|
        Classify.value_not_needed!(t)
        Classify.type_expr!(t)
      end
    else
      raise NotImplementedError.new(refer[qualify.term])
    end
  end
  
  def touch(relate : AST::Relate)
    case relate.op.value
    when "."
      # In a member access Relate, a value is not needed for the right side.
      # A value is only needed for the left side and the overall access node.
      rhs = relate.rhs
      Classify.value_not_needed!(rhs)
      Classify.value_not_needed!(rhs.term) if rhs.is_a?(AST::Qualify)
    end
  end
  
  def touch(node : AST::Node)
    # On all other nodes, do nothing.
  end
end
