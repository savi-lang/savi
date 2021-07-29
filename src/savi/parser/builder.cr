require "pegmatite"

module Savi::Parser::Builder
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
    annotations = [] of AST::Annotation

    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)
      case term
      when AST::Declare then doc.list << (decl = term)
      when AST::Annotation then annotations << term
      else
        decl = decl.as(AST::Declare)

        unless annotations.empty?
          decl.annotations = annotations
          annotations = [] of AST::Annotation
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

  private def self.build_term(main, iter, state)
    kind, start, finish = main
    case kind
    when :decl
      build_decl(main, iter, state)
    when :annotation
      value = state.slice(main)
      AST::Annotation.new(value).with_pos(state.pos(main))
    when :ident
      value = state.slice(main)
      AST::Identifier.new(value).with_pos(state.pos(main))
    when :string
      build_string(main, iter, state)
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

  private def self.build_string(main, iter, state)
    assert_kind(main, :string)
    terms = [] of AST::Term

    # See if this string has a nested identifier and/or string inside it.
    child_ident : AST::Identifier? = nil
    child_string : AST::LiteralString? = nil
    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)
      case term
      when AST::Identifier then child_ident = term
      when AST::LiteralString then child_string = term
      else
        raise NotImplementedError.new(child)
      end
    end

    # If there were child elements inside, use those.
    # Otherwise, this is an inner string so we gather its slice directly.
    if child_string
      child_string.prefix_ident = child_ident
      child_string.with_pos(state.pos(main))
    else
      value = state.slice_with_escapes(main)
      AST::LiteralString.new(value).with_pos(state.pos(main))
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
        pos = state.pos({:group, pos[0], pos[1]})

        # If the partition has any terms, use the span of its terms as its pos.
        if terms.any?
          first_pos = terms.first.pos
          last_pos = terms.last.pos
          pos = Source::Pos.new(
            pos.source,
            first_pos.start,
            last_pos.finish,
            first_pos.line_start,
            first_pos.line_finish,
            first_pos.row,
            first_pos.col,
          )
        end

        AST::Group.new(style, terms).with_pos(pos).as(AST::Node)
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

    group.terms.size == 1 ? group.terms.first : group
  end

  private def self.build_pony_control_block(main, iter, state)
    assert_kind(main, :pony_control_block)
    group = AST::Group.new("(").with_pos(state.pos(main))

    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)

      raise "stray operator: #{term}" if term.is_a?(AST::Operator)

      group.terms << term
    end

    group
  end

  private def self.build_pony_control_if(main, iter, state)
    assert_kind(main, :pony_control_if)
    pos = state.pos(main)
    stack = [] of AST::Term
    list = [] of {AST::Term, AST::Term}

    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)

      raise "stray operator: #{term}" if term.is_a?(AST::Operator)

      if stack.empty?
        stack.push(term)
      else
        list.push({stack.shift(), term})
      end
    end

    unless stack.empty?
      list.push({AST::Identifier.new("True").with_pos(pos), stack.shift()})
    end
    raise "inconsistent logic" unless stack.empty?

    AST::Choice.new(list).with_pos(pos)
  end

  private def self.build_pony_control_while(main, iter, state)
    assert_kind(main, :pony_control_while)
    pos = state.pos(main)
    stack = [] of AST::Term

    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)

      raise "stray operator: #{term}" if term.is_a?(AST::Operator)

      stack.push(term)
    end

    raise "wrong number of terms: #{stack.to_a.inspect}" \
      if stack.size < 2 || stack.size > 3

    cond = stack.shift()
    AST::Loop.new(
      cond,
      stack.shift(),
      cond,
      stack.last? || AST::Identifier.new("None").with_pos(pos),
    ).with_pos(pos)
  end

  private def self.build_pony_control_recover(main, iter, state)
    assert_kind(main, :pony_control_recover)
    pos = state.pos(main)
    stack = [] of AST::Term

    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)

      raise "stray operator: #{term}" if term.is_a?(AST::Operator)

      stack.push(term)
    end

    if stack.size == 1
      AST::Prefix.new(
        AST::Operator.new("recover_UNSAFE").with_pos(pos), # TODO: make recover safe
        stack.shift(),
      ).with_pos(pos)
    elsif stack.size == 2
      raise NotImplementedError.new("pony_control_recover with explicit cap")
    else
      raise "wrong number of terms: #{stack.to_a.inspect}"
    end
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
      when AST::Annotation
        ann = op.as(AST::Annotation)
        (term.annotations ||= [] of AST::Annotation).not_nil! << ann
      else
        raise NotImplementedError.new(child)
      end
    end

    term
  end
end
