class Mare::Compiler::Sugar < Mare::AST::Visitor
  def self.run(ctx)
    sugar = new
    ctx.program.types.each do |t|
      t.functions.each do |f|
        # TODO also run in parameter signature?
        f.body.try { |body| body.accept(sugar) }
      end
    end
  end
  
  def visit(node : AST::Identifier)
    if node.value == "@"
      node
    elsif node.value.char_at(0) == '@'
      lhs = AST::Identifier.new("@").from(node)
      dot = AST::Operator.new(".").from(node)
      rhs = AST::Identifier.new(node.value[1..-1]).from(node)
      AST::Relate.new(lhs, dot, rhs).from(node)
    else
      node
    end
  end
  
  def visit(node : AST::Relate)
    case node.op.value
    when ".", "&&", "||", " " then node # skip these special-case operators
    when "="
      # If assigning to a "." relation, treat as a "setter" method call.
      lhs = node.lhs
      if lhs.is_a?(AST::Relate) && lhs.op.value == "."
        name = "#{lhs.rhs.as(AST::Identifier).value}="
        ident = AST::Identifier.new(name).from(lhs.rhs)
        args = AST::Group.new("(", [node.rhs]).from(node.rhs)
        rhs = AST::Qualify.new(ident, args).from(node)
        AST::Relate.new(lhs.lhs, lhs.op, rhs).from(node)
      else
        node
      end
    else
      # Convert the operator relation into a single-argument method call.
      ident = AST::Identifier.new(node.op.value).from(node.op)
      dot = AST::Operator.new(".").from(node.op)
      args = AST::Group.new("(", [node.rhs]).from(node.rhs)
      rhs = AST::Qualify.new(ident, args).from(node)
      AST::Relate.new(node.lhs, dot, rhs).from(node)
    end
  end
end
