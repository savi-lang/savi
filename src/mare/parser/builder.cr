require "pegmatite"

module Mare::Parser::Builder
  def self.build(tokens, source)
    iter = Pegmatite::TokenIterator.new(tokens)
    main = iter.next
    state = State.new(source)
    build_doc(main, iter, state).tap(&.source=(source))
  end

  private def self.assert_kind(token, kind)
    raise "Unexpected token: #{token.inspect}; expected: #{kind.inspect}" \
      unless token[0] == kind
  end

  private def self.build_doc(main, iter, state)
    assert_kind(main, :doc)
    doc = AST::Document.new
    decl : AST::Declare? = nil
    doc_strings = [] of AST::DocString

    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)
      case term
      when AST::Declare then doc.list << (decl = term)
      when AST::DocString then doc_strings << term
      else
        decl = decl.as(AST::Declare)

        unless doc_strings.empty?
          decl.doc_strings = doc_strings
          doc_strings = [] of AST::DocString
        end

        decl.body.terms << term
        if term.pos.finish > decl.body.pos.finish
          new_pos = decl.body.pos
          new_pos.finish = term.pos.finish
          decl.body.with_pos(new_pos)
        end
      end
    end

    doc
  end

  private def self.build_decl(main, iter, state)
    assert_kind(main, :decl)
    decl = AST::Declare.new.with_pos(state.pos(main))

    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)
      decl.head << term
    end

    decl
  end

  # Special case for Pony - rewrite `let`, `var`, and `embed` as `prop`.
  # TODO: Do something else and actually carry through the Pony distinction?
  private def self.build_pony_prop_decl(main, iter, state)
    assert_kind(main, :pony_prop_decl)
    decl = AST::Declare.new.with_pos(state.pos(main))

    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)
      decl.head << term
    end

    # This part is the special case for Pony - override the head's first ident.
    decl.head.first.as(AST::Identifier).value = "prop"

    decl
  end

  private def self.build_term(main, iter, state)
    kind, start, finish = main
    case kind
    when :decl
      build_decl(main, iter, state)
    when :pony_prop_decl
      build_pony_prop_decl(main, iter, state)
    when :doc_string
      value = state.slice(main)
      AST::DocString.new(value).with_pos(state.pos(main))
    when :ident
      value = state.slice(main)
      AST::Identifier.new(value).with_pos(state.pos(main))
    when :string
      value = state.slice_with_escapes(main)
      AST::LiteralString.new(value).with_pos(state.pos(main))
    when :char
      string = state.slice_with_escapes(main)
      reader = Char::Reader.new(string)
      value = reader.current_char
      if (reader.next_char; reader.has_next?)
        Error.at state.pos(main),
          "This character literal has more than one character in it"
      end

      AST::LiteralCharacter.new(value.ord.to_i64).with_pos(state.pos(main))
    when :heredoc
      value = state.slice(main)
      if (leading_space = value[/(?<=\A\n)[ \t]+/]?; leading_space)
        value = value.gsub("\n#{leading_space}", "\n").strip
      end
      AST::LiteralString.new(value).with_pos(state.pos(main))
    when :integer
      string = state.slice(main)
      value =
        begin
          string.to_u64(underscore: true)
        rescue
          begin
            string.to_i64(underscore: true).to_i64
          rescue
            string.to_u64(underscore: true, prefix: true)
          end
        end
      AST::LiteralInteger.new(value).with_pos(state.pos(main))
    when :float
      value = state.slice(main).to_f
      AST::LiteralFloat.new(value).with_pos(state.pos(main))
    when :op
      value = state.slice(main)
      AST::Operator.new(value).with_pos(state.pos(main))
    when :relate   then build_relate(main, iter, state)
    when :relate_r then build_relate_r(main, iter, state)
    when :group    then build_group(main, iter, state)
    when :group_w  then build_group_w(main, iter, state)
    when :prefix   then build_prefix(main, iter, state)
    when :qualify  then build_qualify(main, iter, state)
    when :compound then build_compound(main, iter, state)
    else
      raise NotImplementedError.new(kind)
    end
  end

  private def self.build_relate(main, iter, state)
    assert_kind(main, :relate)
    terms = [] of AST::Term

    iter.while_next_is_child_of(main) do |child|
      terms << build_term(child, iter, state)
    end

    # Parsing operator precedeence without too much nested backtracking
    # requires us to generate a lot of false positive relates in the grammar
    # (:relate nodes with no operator and only one term); cleanse those here.
    return terms.shift if terms.size == 1

    # Build a left-leaning tree of Relate nodes, each with a left-hand-side,
    # a right-hand-side, and an operator betwixt the two of those terms.
    terms[1..-1].each_slice(2).reduce(terms.first) do |lhs, (op, rhs)|
      AST::Relate.new(lhs, op.as(AST::Operator), rhs).with_pos(state.pos(main))
    end
  end

  private def self.build_relate_r(main, iter, state)
    assert_kind(main, :relate_r)
    terms = [] of AST::Term

    iter.while_next_is_child_of(main) do |child|
      terms << build_term(child, iter, state)
    end

    # Parsing operator precedeence without too much nested backtracking
    # requires us to generate a lot of false positive relates in the grammar
    # (:relate_r nodes with no operator and only one term); cleanse those here.
    return terms.shift if terms.size == 1

    # Build a right-leaning tree of Relate nodes, each with a left-hand-side,
    # a right-hand-side, and an operator betwixt the two of those terms.
    terms[0...-1].reverse.each_slice(2).reduce(terms.last) do |rhs, (op, lhs)|
      AST::Relate.new(lhs, op.as(AST::Operator), rhs).with_pos(state.pos(main))
    end
  end

  private def self.build_group(main, iter, state)
    assert_kind(main, :group)
    style = state.slice(main[1]..main[1])

    # This handles the case of an group ending with an exclamation
    # by adding that character to its "style" string.
    last_char = state.slice((main[2] - 1)..(main[2] - 1))
    style += "!" if last_char == "!"

    terms_lists = [[] of AST::Term]
    partitions = [main[1] + 1]

    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)

      if term.is_a?(AST::Operator)
        raise "stray operator: #{term}" unless term.value == "|"

        # This is a partition operator; create a new partition.
        partitions << child[1] << child[2]
        terms_lists << [] of AST::Term
      else
        # Otherwise, insert into the current partition as normal.
        terms_lists.last << term
      end
    end

    if terms_lists.size <= 1
      # This is a flat group with just one partition.
      AST::Group.new(style, terms_lists.first).with_pos(state.pos(main))
    else
      # This is a partitioned group, built as a nested group.
      partitions << main[2] - 1
      positions = partitions.each_slice(2).to_a
      top_terms = terms_lists.zip(positions).map do |terms, pos|
        pos = {:group, pos[0], pos[1]}
        AST::Group.new(style, terms).with_pos(state.pos(pos)).as(AST::Node)
      end
      AST::Group.new("|", top_terms).with_pos(state.pos(main))
    end
  end

  private def self.build_group_w(main, iter, state)
    assert_kind(main, :group_w)
    group = AST::Group.new(" ").with_pos(state.pos(main))

    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)

      raise "stray operator: #{term}" if term.is_a?(AST::Operator)

      group.terms << term
    end

    group
  end

  private def self.build_prefix(main, iter, state)
    assert_kind(main, :prefix)

    op = build_term(iter.next_as_child_of(main), iter, state)
    op = op.as(AST::Operator)

    term = build_term(iter.next_as_child_of(main), iter, state)

    AST::Prefix.new(op, term).with_pos(state.pos(main))
  end

  private def self.build_qualify(main, iter, state)
    assert_kind(main, :qualify)

    term = build_term(iter.next_as_child_of(main), iter, state)

    iter.while_next_is_child_of(main) do |child|
      group = build_group(child, iter, state)
      group = group.as(AST::Group)

      term = AST::Qualify.new(term, group).with_pos(state.pos(main))
    end

    term
  end

  private def self.build_compound(main, iter, state)
    assert_kind(main, :compound)

    term = build_term(iter.next_as_child_of(main), iter, state)

    iter.while_next_is_child_of(main) do |child|
      op = build_term(child, iter, state)
      case op
      when AST::Operator
        rhs = build_term(iter.next_as_child_of(main), iter, state)
        term = AST::Relate.new(term, op, rhs).with_pos(state.pos(main))
      when AST::Group
        term = AST::Qualify.new(term, op).with_pos(state.pos(main))
      else
        raise NotImplementedError.new(child)
      end
    end

    term
  end
end
