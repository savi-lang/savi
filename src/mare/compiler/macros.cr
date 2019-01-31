class Mare::Compiler::Macros < Mare::AST::Visitor
  # TODO: This class should interpret macro declarations by the user and treat
  # those the same as macro declarations in the prelude, with both getting
  # executed here dynamically instead of declared here statically.
  
  def self.run(ctx)
    macros = new
    ctx.program.types.each do |t|
      t.functions.each do |f|
        # TODO also run in parameter signature?
        f.body.try { |body| body.accept(macros) }
      end
    end
  end
  
  def visit(node : AST::Group)
    # Handle only groups that are whitespace-delimited, as these are the only
    # groups that we may match and interpret as if they are macros.
    return node unless node.style == " "
    
    if Util.match_ident?(node, 0, "if")
      Util.require_terms(node, [
        nil,
        "the condition to be satisfied",
        "the body to be conditionally executed,\n" \
        "  including an optional else clause partitioned by `|`",
      ])
      visit_if(node)
    else
      node
    end
  end
  
  def visit_if(node : AST::Group)
    if_ident = node.terms[0]
    cond = node.terms[1]
    body = node.terms[2] # TODO: handle else clause delimited by `|`
    
    if body.is_a?(AST::Group) && body.style == "|"
      Util.require_terms(body, [
        "the body to be executed when the condition is true",
        "the body to be executed otherwise (the \"else\" case)",
      ], true)
      
      clauses = [
        {cond, body.terms[0]},
        {AST::Identifier.new("True").from(if_ident), body.terms[1]},
      ]
    else
      clauses = [{cond, body}]
      
      # Create an implicit else clause that covers all remaining cases.
      # TODO: add a pass to detect a Choice that doesn't have this,
      # or maybe implicitly assume it later without adding it to the AST?
      clauses << {
        AST::Identifier.new("True").from(if_ident),
        AST::Identifier.new("None").from(if_ident),
      }
    end
    
    group = AST::Group.new("(").from(node)
    group.terms << AST::Choice.new(clauses).from(if_ident)
    group
  end
end
