require "pegmatite"

module Mare::Parser::Builder
  def self.build(tokens, source)
    iter = Pegmatite::TokenIterator.new(tokens)
    main = iter.next
    build_doc(main, iter, source)
  end
  
  private def self.assert_kind(token, kind)
    raise "Unexpected token: #{token.inspect}; expected: #{kind.inspect}" \
      unless token[0] == kind
  end
  
  private def self.build_doc(main, iter, source)
    assert_kind(main, :doc)
    doc = AST::Document.new
    decl : AST::Declare? = nil
    
    iter.while_next_is_child_of(main) do |child|
      if child[0] == :decl
        decl = build_decl(child, iter, source)
        doc.list << decl
      else
        term = build_term(child, iter, source)
        decl.as(AST::Declare).body.terms << term
      end
    end
    
    doc
  end
  
  private def self.build_decl(main, iter, source)
    assert_kind(main, :decl)
    decl = AST::Declare.new.with_pos(source, main)
    
    iter.while_next_is_child_of(main) do |child|
      decl.head << build_term(child, iter, source)
    end
    
    decl
  end
  
  private def self.build_term(main, iter, source)
    kind, start, finish = main
    case kind
    when :ident
      value = source.content[start...finish]
      AST::Identifier.new(value).with_pos(source, main)
    when :string
      value = source.content[start...finish]
      AST::LiteralString.new(value).with_pos(source, main)
    when :integer
      value = source.content[start...finish].to_u64
      AST::LiteralInteger.new(value).with_pos(source, main)
    when :float
      value = source.content[start...finish].to_f
      AST::LiteralFloat.new(value).with_pos(source, main)
    when :op
      value = source.content[start...finish]
      AST::Operator.new(value).with_pos(source, main)
    when :relate  then build_relate(main, iter, source)
    when :group   then build_group(main, iter, source)
    when :group_w then build_group_w(main, iter, source)
    when :prefix  then build_prefix(main, iter, source)
    when :qualify then build_qualify(main, iter, source)
    else
      raise NotImplementedError.new(kind)
    end
  end
  
  private def self.build_relate(main, iter, source)
    assert_kind(main, :relate)
    terms = [] of AST::Term
    
    iter.while_next_is_child_of(main) do |child|
      terms << build_term(child, iter, source)
    end
    
    # Parsing operator precedeence without too much nested backtracking
    # requires us to generate a lot of false positive relates in the grammar
    # (:relate nodes with no operator and only one term); cleanse those here.
    return terms.shift if terms.size == 1
    
    # Build a left-leaning tree of Relate nodes, each with a left-hand-side,
    # a right-hand-side, and an operator betwixt the two of those terms.
    terms.each_slice(2).reduce(terms.shift) do |lhs, (op, rhs)|
      AST::Relate.new(lhs, op.as(AST::Operator), rhs).with_pos(source, main)
    end
  end
  
  private def self.build_group(main, iter, source)
    assert_kind(main, :group)
    style = source.content[main[1]..main[1]]
    terms_lists = [[] of AST::Term]
    partitions = [main] # TODO: use the appropriate subset span of main
    
    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, source)
      
      if term.is_a?(AST::Operator)
        raise "stray operator: #{term}" unless term.value == "|"
        
        # This is a partition operator; create a new partition.
        partitions << child
        terms_lists << [] of AST::Term
      else
        # Otherwise, insert into the current partition as normal.
        terms_lists.last << term
      end
    end
    
    if terms_lists.size <= 1
      # This is a flat group with just one partition.
      AST::Group.new(style, terms_lists.first).with_pos(source, main)
    else
      # This is a partitioned group, built as a nested group.
      top_terms = terms_lists.zip(partitions).map do |terms, pos|
        AST::Group.new(style, terms).with_pos(source, pos).as(AST::Node)
      end
      AST::Group.new("|", top_terms).with_pos(source, main)
    end
  end
  
  private def self.build_group_w(main, iter, source)
    assert_kind(main, :group_w)
    group = AST::Group.new(" ").with_pos(source, main)
    
    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, source)
      
      raise "stray operator: #{term}" if term.is_a?(AST::Operator)
      
      group.terms << term
    end
    
    group
  end
  
  private def self.build_prefix(main, iter, source)
    assert_kind(main, :prefix)
    
    op = build_term(iter.next_as_child_of(main), iter, source)
    op = op.as(AST::Operator)
    
    term = build_term(iter.next_as_child_of(main), iter, source)
    
    AST::Prefix.new(op, term).with_pos(source, main)
  end
  
  private def self.build_qualify(main, iter, source)
    assert_kind(main, :qualify)
    
    term = build_term(iter.next_as_child_of(main), iter, source)
    
    group = build_term(iter.next_as_child_of(main), iter, source)
    group = group.as(AST::Group)
    
    AST::Qualify.new(term, group).with_pos(source, main)
  end
end
