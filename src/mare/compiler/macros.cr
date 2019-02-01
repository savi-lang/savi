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
    elsif Util.match_ident?(node, 0, "case")
      Util.require_terms(node, [
        nil,
        "the group of cases to check, partitioned by `|`",
      ])
      visit_case(node)
    else
      node
    end
  end
  
  def visit_if(node : AST::Group)
    orig = node.terms[0]
    cond = node.terms[1]
    body = node.terms[2]
    
    if body.is_a?(AST::Group) && body.style == "|"
      Util.require_terms(body, [
        "the body to be executed when the condition is true",
        "the body to be executed otherwise (the \"else\" case)",
      ], true)
      
      clauses = [
        {cond, body.terms[0]},
        {AST::Identifier.new("True").from(orig), body.terms[1]},
      ]
    else
      clauses = [{cond, body}]
      
      # Create an implicit else clause that covers all remaining cases.
      # TODO: add a pass to detect a Choice that doesn't have this,
      # or maybe implicitly assume it later without adding it to the AST?
      clauses << {
        AST::Identifier.new("True").from(orig),
        AST::Identifier.new("None").from(orig),
      }
    end
    
    group = AST::Group.new("(").from(node)
    group.terms << AST::Choice.new(clauses).from(orig)
    group
  end
  
  def visit_case(node : AST::Group)
    orig = node.terms[0]
    group = node.terms[1]
    
    Error.at group,
      "Expected this term to be a parenthesized group of cases to check,\n" \
      "  partitioned into sections by `|`, in which each body section\n" \
      "  is preceded by a condition section to be evaluated as a Bool,\n" \
      "  with an optional else body section at the end" \
        unless group.is_a?(AST::Group) && group.style == "|"
    
    # By construction, every term in a `|` group must be a `(` group.
    sections = group.as(AST::Group).terms.map(&.as(AST::Group))
    
    # Discard an empty section at the beginning if present.
    # This gives aesthetic alternatives for single vs multi-line renderings.
    sections.shift if sections.first.terms.empty?
    
    # Add a condition and case body for each pair of sections we encounter.
    clauses = [] of {AST::Term, AST::Term}
    while sections.size >= 2
      cond = sections.shift
      body = sections.shift
      clauses << {cond, body}
    end
    
    # Add an else case at the end. This has an implicit value of None,
    # unless the number of total sections was odd, in which case the last
    # section is counted as being the body to execute in the else case.
    # TODO: add a pass to detect a Choice that doesn't have this,
    # or maybe implicitly assume it later without adding it to the AST?
    clauses << {
      AST::Identifier.new("True").from(orig),
      sections.empty? ? AST::Identifier.new("None").from(orig) : sections.pop
    }
    
    group = AST::Group.new("(").from(node)
    group.terms << AST::Choice.new(clauses).from(orig)
    group
  end
end
