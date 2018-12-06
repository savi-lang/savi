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
  
  def visit(node : AST::Relate)
    case node.op.value
    when ".", "&&", "||", " ", "=" then node # skip these special-case operators
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
