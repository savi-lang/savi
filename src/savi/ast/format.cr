class Savi::AST::Format < Savi::AST::Visitor
  # Return a list of edits that should be applied to the given document.
  def self.run(
    ctx : Compiler::Context,
    package : Program::Package::Link,
    docs : Array(AST::Document)
  )
    docs.compact_map { |doc|
      visitor = new(package, doc)
      doc.accept(ctx, visitor)
      visitor.finalize
      edits = visitor.edits
      next if edits.empty?
      {doc, edits}
    }.to_h
  end

  # Emit errors to the context for any formatting issues in the given document.
  def self.check(
    ctx : Compiler::Context,
    package : Program::Package::Link,
    docs : Array(AST::Document)
  )
    run(ctx, package, docs).each { |doc, edits|
      edits.each { |edit|
        ctx.error_at edit.pos, "This code violates formatting rule #{edit.rule}"
      }
    }
  end

  enum Rule
    Indentation
    NoUnnecessaryParens
    NoSpaceInsideBrackets
    SpaceAroundPipeSeparator
    NoTrailingCommas
    NoSpaceBeforeComma
    SpaceAfterComma
    NoExplicitSelfDot
  end

  struct Edit
    getter rule : Rule
    getter pos : Source::Pos
    getter replacement : String

    def initialize(@rule, @pos, @replacement)
    end
  end

  getter edits = [] of Edit

  def initialize(package : Program::Package::Link, doc : AST::Document)
    @parent_stack = [] of AST::Node
    @indent_state = IndentState.new(package, doc)
  end

  def finalize
    @indent_state.each_indent_violation { |pos, replacement|
      violates Rule::Indentation, pos, replacement
    }
  end

  def parent
    @parent_stack.last
  end

  def violates(rule, pos, replacement = "")
    @edits << Edit.new(rule, pos, replacement)
  end

  def visit_pre(ctx, node : AST::Node)
    @indent_state.visit_pre(ctx, self, node)
    @parent_stack << node
  end

  def visit(ctx, node : AST::Node)
    @parent_stack.pop
    @indent_state.visit_post(ctx, self, node)
    observe(ctx, node)
  end

  def observe(ctx, group : AST::Group)
    observe_group_brackets(ctx, group)
    observe_group_commas(ctx, group)
    observe_group_term_parens(ctx, group)
  end

  def observe_group_brackets(ctx, group : AST::Group)
    case group.style
    when " ", ":" then
      # No bracket analysis for these kinds of groups
      return
    when "("
      # No bracket analysis for pipe-separated inner groups.
      parent = parent()
      return if parent.is_a?(AST::Group) && parent.style == "|"
    end

    # Check for unwanted space inside the opening bracket.
    first_term = group.terms.first?
    first_term_pos = first_term.try(&.pos)
    if (
      group.pos.single_line? ||
      (
        first_term_pos && first_term_pos.size > 0 &&
        group.pos.contains_on_first_line?(first_term_pos) &&
        !first_term_pos.content.match(/\A\s*\n/)
      )
    ) && (
      pos = group.pos.content_match_as_pos(/\A[\[({](\s+)/, 1)
    )
      violates Rule::NoSpaceInsideBrackets, pos
    end

    # Check for unwanted space inside the closing bracket.
    last_term = group.terms.last?
    last_term_pos = last_term.try(&.pos)
    if (
      last_term_pos && last_term_pos.size > 0 &&
      group.pos.contains_on_last_line?(last_term_pos) &&
      !last_term_pos.content.match(/\n\s*\z/)
    ) && (
      pos = group.pos.content_match_as_pos(/(\s+)[\])}]\z/, 1)
    )
      violates Rule::NoSpaceInsideBrackets, pos
    end

    # Check for wanted space around the pipe separators.
    if group.style == "|"
      group.terms.each_with_index { |term, index|
        next if term.is_a?(AST::Group) && term.terms.empty?

        # Check for wanted space after a pipe separator.
        if index > 0 && (
          pos = term.pos.pre_match_as_pos(/\|()\z/, 1)
        )
          violates Rule::SpaceAroundPipeSeparator, pos, " "
        end

        # Check for wanted space before a pipe separator.
        if index < group.terms.size - 1 && (
          pos = term.pos.post_match_as_pos(/\G()\|/, 1)
        )
          violates Rule::SpaceAroundPipeSeparator, pos, " "
        end
      }
    end
  end

  def observe_group_commas(ctx, group : AST::Group)
    return if group.style == " " # no comma analysis for whitespace-style groups

    group.terms.each_with_index { |term, index|
      term_pos = term.pos
      next_term_pos = group.terms[index + 1]?.try(&.pos)

      next_term_same_line =
        next_term_pos && term_pos.precedes_on_same_line?(next_term_pos)
      if next_term_same_line
        # Check for unwanted space before the comma.
        if (pos = term_pos.post_match_as_pos(/\G\s+(?=,)/))
          violates Rule::NoSpaceBeforeComma, pos
        end

        # Check for wanted space after the comma.
        if (pos = term_pos.post_match_as_pos(/\G\s*,((?=\S))/, 1))
          violates Rule::SpaceAfterComma, pos, " "
        end
      else
        # Check for unwanted trailing comma.
        if (pos = term_pos.post_match_as_pos(/\G\s*,/))
          violates Rule::NoTrailingCommas, pos
        end
      end
    }
  end

  # Check for unnecessary parens within the terms of a Group.
  def observe_group_term_parens(ctx, group : AST::Group)
    return if group.style == "|" # don't look at pipe-separated groups groupings

    group.terms.each { |term|
      # Only consider a term that is a parens group.
      next unless term.is_a?(AST::Group) && term.style == "("

      if group.style == " "
        # Parens for readability are acceptable when they are multi-line.
        next unless term.pos.single_line?

        # Parens may be necessary only when there is more than one term inside.
        next unless term.terms.size == 1
        term_term = term.terms.first

        # Dig through nested parens if present.
        while term_term.is_a?(AST::Group) \
          && term_term.style == "(" \
          && term_term.terms.size == 1
          term_term = term_term.terms.first
        end

        # Parens are necessary to delineate one whitespace-group from another.
        next if term_term.is_a?(AST::Group) && term_term.style == " "

        # Parens are necessary for an assign relate inside a whitespace-group.
        next if term_term.is_a?(AST::Relate) && term_term.is_assign
      end

      # If we get to this point, the parens are considered unnecessary.
      pos = term.pos
      violates Rule::NoUnnecessaryParens, pos.subset(0, pos.size - 1)
      violates Rule::NoUnnecessaryParens, pos.subset(pos.size - 1, 0)
    }
  end

  def observe(ctx, relate : AST::Relate)
    observe_relate_dot(ctx, relate)
    observe_relate_term_parens(ctx, relate)
  end

  def observe_relate_dot(ctx, relate : AST::Relate)
    return if relate.op.value != "." # only look at dot-relations
    lhs = relate.lhs
    rhs = relate.rhs

    # Check for unwanted explicit "self dot".
    if lhs.is_a?(AST::Identifier) && lhs.value == "@"
      violates Rule::NoExplicitSelfDot,
        Source::Pos.index_range(lhs.pos.source, lhs.pos.finish, rhs.pos.start)
    end
  end

  # Check for unnecessary parens within the terms of a Relate.
  def observe_relate_term_parens(ctx, relate : AST::Relate)
    # Don't look at dot-relations or arrow-relations.
    return if relate.op.value == "." || relate.op.value == "->"

    [relate.lhs, relate.rhs].each { |term|
      # Only consider a term that is a parens group.
      next unless term.is_a?(AST::Group) && term.style == "("

      # Parens for readability are acceptable when they are multi-line.
      next unless term.pos.single_line?

      # Parens may be necessary only when there is more than one term inside.
      next unless term.terms.size == 1
      term_term = term.terms.first

      # Dig through nested parens if present.
      while term_term.is_a?(AST::Group) \
        && term_term.style == "(" \
        && term_term.terms.size == 1
        term_term = term_term.terms.first
      end

      # Parens for disambiguating precedence of another relate are acceptable.
      next if term_term.is_a?(AST::Relate)

      # Parens for disambiguating precedence of a qualify are acceptable.
      next if term_term.is_a?(AST::Qualify)

      # Parens are necessary for a whitespace group in a surrounding relate,
      # unless the relate is an assignment (in which case they are unnecessary).
      next if term_term.is_a?(AST::Group) && term_term.style == " " && !relate.is_assign

      # If we get to this point, the parens are considered unnecessary.
      pos = term.pos
      violates Rule::NoUnnecessaryParens, pos.subset(0, pos.size - 1)
      violates Rule::NoUnnecessaryParens, pos.subset(pos.size - 1, 0)
    }
  end

  # For all other nodes, we analyze nothing.
  def observe(ctx, node)
  end
end
