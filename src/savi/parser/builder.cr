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
    doc = AST::Document.new.with_pos(state.source.entire_pos)
    decl : AST::Declare? = nil
    body = AST::Group.new(":")
    annotations = [] of AST::Annotation

    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)
      case term
      when AST::Annotation then annotations << term
      when AST::Declare
        decl = term

        unless annotations.empty?
          decl.annotations = annotations
          annotations = [] of AST::Annotation
        end

        unless body.terms.empty?
          body.with_pos(body.terms.first.pos.span([body.terms.last.pos]))
          doc.list << body
          body = AST::Group.new(":")
        end

        doc.list << decl
      else
        body.terms << term
      end
    end

    unless body.terms.empty?
      body.with_pos(body.terms.first.pos.span([body.terms.last.pos]))
      doc.list << body
      body = AST::Group.new(":")
    end

    doc
  end

  private def self.build_decl(main, iter, state)
    assert_kind(main, :decl)
    decl = AST::Declare.new.with_pos(state.pos(main))

    iter.while_next_is_child_of(main) do |child|
      decl.terms << build_term(child, iter, state)
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
      value = state.slice(main).gsub('_', "").to_f
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
    # It may also have interpolated terms inside of it.
    child_ident : AST::Identifier? = nil
    child_string : (AST::LiteralString | AST::ComposeString)? = nil
    child_interpolations = [] of AST::Term
    child_interpolation_tokens = [] of Pegmatite::Token
    iter.while_next_is_child_of(main) do |child|
      term = build_term(child, iter, state)
      case term
      when AST::Identifier then child_ident = term
      when AST::LiteralString then child_string = term
      when AST::ComposeString then child_string = term
      when AST::Group
        child_interpolations << term
        child_interpolation_tokens << child
      else
        raise NotImplementedError.new(child)
      end
    end

    # If there were child elements inside, use those.
    # Otherwise, this is an inner string so we gather its slice directly.
    if child_string.is_a?(AST::LiteralString)
      child_string.prefix_ident = child_ident
      child_string.with_pos(state.pos(main))
    elsif child_string.is_a?(AST::ComposeString)
      child_string.prefix_ident = child_ident
      child_string.with_pos(state.pos(main))
    elsif child_interpolation_tokens.any?
      compose = AST::ComposeString.new.with_pos(state.pos(main))
      token_partition(main, child_interpolation_tokens) { |part, index_in_list, part_is_final|
        if index_in_list
          compose.terms << child_interpolations[index_in_list]
        else
          # If this isn't the final part, then it has a trailing '\' in it
          # which is the prefix of the interpolated group that comes next.
          # We don't want to count this `\` as being part of the literal string,
          # so we amend the part tuple here to exclude it from consideration.
          part = {part[0], part[1], part[2] - 1} unless part_is_final

          # If this is an empty string literal, we need not include it.
          # At best it will have no effect, and at worst it is wasteful.
          part_is_empty = part[1] == part[2]
          next if part_is_empty

          compose.terms << AST::LiteralString.new(
            state.slice_with_escapes(part)
          ).with_pos(state.pos(part))
        end
      }
      compose
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
      AST::Relate.new(lhs, op.as(AST::Operator), rhs).with_pos(
        lhs.pos.span([rhs.pos])
      )
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
      AST::Relate.new(lhs, op.as(AST::Operator), rhs).with_pos(
        lhs.pos.span([rhs.pos])
      )
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
        pos = state.pos({:group, pos[0], pos[0]})

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

      term = AST::Qualify.new(term, group).with_pos(
        term.pos.span([group.pos])
      )
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
        term = AST::Relate.new(term, op, rhs).with_pos(
          term.pos.span([op.pos, rhs.pos])
        )
      when AST::Group
        term = AST::Qualify.new(term, op).with_pos(
          term.pos.span([op.pos])
        )
      when AST::Annotation
        ann = op.as(AST::Annotation)
        (term.annotations ||= [] of AST::Annotation).not_nil! << ann
      else
        raise NotImplementedError.new(child)
      end
    end

    term
  end

  # Given a "main" token and a list of tokens contained within its span,
  # partition the main token into ordered sub-tokens, some of which are
  # from the given list, and the rest of which are the parts between those.
  #
  # For example, this function is used to partition an interpolated string
  # into its parts, including the dynamic value expressions in the list
  # and the static value string literal portions between those expressions.
  #
  # Note that this function assumes the given list is in order.
  # It also assumes that all list tokens are contained within the main token.
  # If either of these invariants don't hold, the behavior is unspecified.
  private def self.token_partition(
    main : Pegmatite::Token,
    list : Array(Pegmatite::Token)
  )
    # Begin from the start of the main token.
    cursor = main[1]

    list.each_with_index { |list_part, index_in_list|
      # If the cursor hasn't reached the current list part token, then we will
      # yield the portion of the main token that precedes the list part token,
      # and move the cursor forward to the start of the list part token.
      if cursor < list_part[1]
        pre_part = {main[0], cursor, list_part[1]}
        yield pre_part, nil, false
        cursor = list_part[1]
      end

      # Now we yield the list part token itself, and move the cursor to its end.
      yield list_part, index_in_list, false
      cursor = list_part[2]
    }

    # If there is any content left in the main token, yield what remains.
    if cursor < main[2]
      post_part = {main[0], cursor, main[2]}
      yield post_part, nil, true
    end

    nil
  end
end
