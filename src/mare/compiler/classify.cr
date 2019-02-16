class Mare::Compiler::Classify < Mare::AST::Visitor
  FLAG_VALUE_NOT_NEEDED = 0x1_u64
  
  def self.value_not_needed?(node); (node.flags & FLAG_VALUE_NOT_NEEDED) != 0 end
  def self.value_needed?(node);     (node.flags & FLAG_VALUE_NOT_NEEDED) == 0 end
  def self.value_not_needed!(node); node.flags |= FLAG_VALUE_NOT_NEEDED end
  def self.value_needed!(node);     node.flags &= ~FLAG_VALUE_NOT_NEEDED end
  
  # This visitor marks the given node and all nodes within as value_not_needed.
  class ValueNotNeededVisitor < Mare::AST::Visitor
    def visit(node)
      Classify.value_not_needed!(node)
      node
    end
  end
  
  def self.run(ctx)
    ctx.program.types.each do |t|
      t.functions.each do |f|
        new.run(f)
      end
    end
  end
  
  def run(func)
    func.params.try(&.accept(self))
    func.ret.try(&.accept(self))
    func.ret.try(&.accept(ValueNotNeededVisitor.new))
    func.body.try(&.accept(self))
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
        group.terms[1].accept(ValueNotNeededVisitor.new)
      else
        raise NotImplementedError.new(group.to_a.inspect)
      end
    end
  end
  
  # However, in a Qualify, a value is needed in all terms of its Group.
  def touch(qualify : AST::Qualify)
    qualify.group.terms.each { |t| Classify.value_needed!(t) }
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
