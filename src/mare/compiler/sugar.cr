class Mare::Compiler::Sugar < Mare::AST::Visitor
  def self.run(ctx)
    sugar = new
    ctx.program.types.each do |t|
      t.functions.each do |f|
        sugar.run(f)
      end
    end
  end
  
  def run(f)
    # If any parameters contain assignments, convert them to defaults.
    if f.body && f.params
      f.params.not_nil!.terms.each do |param|
        if param.is_a?(AST::Relate) && param.op.value == "="
          param.op.value = "DEFAULTPARAM"
        end
      end
    end
    
    # Sugar the parameter signature and return type.
    f.params.try(&.accept(self))
    f.ret.try(&.accept(self))
    
    # If any parameters contain assignables, make assignments in the body.
    if f.body && f.params
      f.params.not_nil!.terms.each_with_index do |param, index|
        # Dig through a default parameter value relation first if present.
        if param.is_a?(AST::Relate) && param.op.value == "DEFAULTPARAM"
          orig_param_with_default = param
          param = param.lhs
        end
        
        # If the param is a dot relation, treat it as an assignable.
        if param.is_a?(AST::Relate) && param.op.value == "."
          new_name = "ASSIGNPARAM.#{index}"
          
          # Replace the parameter with our new name as the identifier.
          param_ident = AST::Identifier.new(new_name).from(param)
          if orig_param_with_default
            orig_param_with_default.lhs = param_ident
          else
            f.params.not_nil!.terms[index] = param_ident
          end
          
          # Add the assignment statement to the top of the function body.
          op = AST::Operator.new("=").from(param)
          assign = AST::Relate.new(param, op, param_ident.dup).from(param)
          f.body.not_nil!.terms.unshift(assign)
        end
      end
    end
    
    # Sugar the body.
    f.body.try { |body| body.accept(self) }
  end
  
  @last_choice_num = 0
  private def next_choice_name
    "choice.#{@last_choice_num += 1}"
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
  
  def visit(node : AST::Qualify)
    # Transform square-brace qualifications into method calls
    if node.group.style == "["
      lhs = node.term
      node.term = AST::Identifier.new("[]").from(node.group)
      args = node.group.tap { |n| n.style = "(" }
      dot = AST::Operator.new(".").from(node.group)
      rhs = node
      return AST::Relate.new(lhs, dot, rhs).from(node)
    end
    
    # If a dot relation is within a qualify (which doesn't happen in the parser,
    # but may happen artifically such as the `@identifier` sugar above),
    # then always move the qualify into the right-hand-side of the dot.
    new_top = nil
    while (dot = node.term).is_a?(AST::Relate) && dot.op.value == "."
      node.term = dot.rhs
      dot.rhs = node
      new_top ||= dot
    end
    new_top || node
  end
  
  def visit(node : AST::Relate)
    case node.op.value
    when ".", "'", " ", "<:", "DEFAULTPARAM"
      node # skip these special-case operators
    when "="
      # If assigning to a ".[identifier]" relation, sugar as a "setter" method.
      lhs = node.lhs
      if lhs.is_a?(AST::Relate) \
      && lhs.op.value == "." \
      && lhs.rhs.is_a?(AST::Identifier)
        name = "#{lhs.rhs.as(AST::Identifier).value}="
        ident = AST::Identifier.new(name).from(lhs.rhs)
        args = AST::Group.new("(", [node.rhs]).from(node.rhs)
        rhs = AST::Qualify.new(ident, args).from(node)
        AST::Relate.new(lhs.lhs, lhs.op, rhs).from(node)
      else
        node
      end
    when "&&"
      # Convert into a choice modeling a short-circuiting logical "AND".
      # Create a choice that executes and returns the rhs expression
      # if the lhs expression is True, and otherwise returns False.
      AST::Choice.new([
        {node.lhs, node.rhs},
        {AST::Identifier.new("True").from(node.op),
          AST::Identifier.new("False").from(node.op)},
      ]).from(node.op)
    when "||"
      # Convert into a choice modeling a short-circuiting logical "OR".
      # Create a choice that returns True if the lhs expression is True,
      # and otherwise executes and returns the rhs expression.
      AST::Choice.new([
        {node.lhs, AST::Identifier.new("True").from(node.op)},
        {AST::Identifier.new("True").from(node.op), node.rhs},
      ]).from(node.op)
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
