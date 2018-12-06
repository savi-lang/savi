class Mare::Compiler::Macros < Mare::AST::Visitor
  # TODO: This class should interpret macro declarations by the user and treat
  # those the same as macro declarations in the prelude, with both getting
  # executed here dynamically instead of declared here statically.
  
  class Error < Exception
  end
  
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
    
    if match_ident?(node, 0, "if")
      require_terms(node, [
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
  
  def match_ident?(node : AST::Group, index : Int32, value : String? = nil)
    child = node.terms[index]?
    return false unless child.is_a?(AST::Identifier)
    return false unless value.nil? || value == child.value
    true
  end
  
  def require_terms(node : AST::Group, term_docs : Array(String?))
    if node.terms.size > term_docs.size
      list = [] of String
      list << "This macro has too many terms:"
      list << node.pos.show
      
      index = -1
      while (index += 1) < node.terms.size
        if index < term_docs.size
          if term_docs[index]
            list << "- this term is #{term_docs[index]}:"
            list << node.terms[index].pos.show
          end
        else
          list << "- this is an excessive term:"
          list << node.terms[index].pos.show
        end
      end
      
      raise Error.new(list.join("\n"))
    end
    
    if node.terms.size < term_docs.size
      list = [] of String
      list << "This macro has too few terms:"
      list << node.pos.show
      
      index = -1
      while (index += 1) < term_docs.size
        if index < node.terms.size
          if term_docs[index]
            list << "- this term is #{term_docs[index]}:"
            list << node.terms[index].pos.show
          end
        else
          list << "- expected a term: #{term_docs[index]}"
        end
      end
      
      raise Error.new(list.join("\n"))
    end
  end
  
  def visit_if(node : AST::Group)
    if_ident = node.terms[0]
    cond = node.terms[1]
    body = node.terms[2] # TODO: handle else clause delimited by `|`
    
    group = AST::Group.new("(").from(node)
    group.terms << AST::Choice.new([{cond, body}]).from(if_ident)
    group
  end
end
