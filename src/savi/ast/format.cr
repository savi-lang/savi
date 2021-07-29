class Savi::AST::Format < Savi::AST::Visitor
  # Return a list of edits that should be applied to the given document.
  def self.run(ctx, doc : AST::Document)
    visitor = new
    doc.accept(ctx, visitor)
    visitor.edits
  end

  # Emit errors to the context for any formatting issues in the given document.
  def self.check(ctx, doc : AST::Document)
    run(ctx, doc).each { |edit|
      ctx.error_at edit.pos, "This code violates formatting rule #{edit.rule}"
    }
  end

  # Apply a list of edits to the source content within the given position,
  # ignoring any edits that fall outside the range of that position.
  # A new source position is returned, pointing to the same region within
  # the a new source that holds the edited content.
  def self.apply_edits(within : Source::Pos, edits : Array(Edit))
    source = within.source
    used_edits = [] of Edit
    chunks = [] of String
    size_delta = 0
    cursor = 0

    # Gather the chunks to reconstruct the edited source.
    edits.group_by(&.pos.start).to_a.sort_by(&.first).each { |start, edits_group|
      edits_group.uniq.sort_by(&.pos.size).each { |edit|
        next unless within.contains?(edit.pos)
        used_edits << edit

        prior_content = source.content.byte_slice(cursor, start - cursor)
        chunks << prior_content unless prior_content.empty?
        chunks << edit.replacement unless edit.replacement.empty?

        size_delta += edit.replacement.bytesize - edit.pos.size

        cursor = edit.pos.finish
      }
    }
    chunks << source.content.byte_slice(cursor, source.content.bytesize - cursor)

    # Return a new source position within a new source that has edited content.
    new_pos = Source::Pos.index_range(
      Source.new(
        source.dirname,
        source.filename,
        chunks.join, # new content
        source.library,
        source.language,
      ),
      within.start,
      within.finish + size_delta,
    )
    {new_pos, used_edits}
  end

  enum Rule
    NoSpaceInsideBrackets
    NoTrailingCommas
    NoSpaceBeforeComma
    SpaceAfterComma
  end

  struct Edit
    getter rule : Rule
    getter pos : Source::Pos
    getter replacement : String

    def initialize(@rule, @pos, @replacement)
    end
  end

  getter edits = [] of Edit

  def initialize
    @parent_stack = [] of AST::Node
  end

  def parent
    @parent_stack.last
  end

  def violates(rule, pos, replacement = "")
    @edits << Edit.new(rule, pos, replacement)
  end

  def visit_pre(ctx, node : AST::Node)
    @parent_stack << node
  end

  def visit(ctx, node : AST::Node)
    @parent_stack.pop
    observe(ctx, node)
  end

  def observe(ctx, group : AST::Group)
    observe_group_brackets(ctx, group)
    observe_group_commas(ctx, group)
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
    first_term_pos = group.terms.first?.try(&.pos)
    if (
      group.pos.single_line? ||
      (
        first_term_pos &&
        group.pos.contains_on_first_line?(first_term_pos) &&
        !first_term_pos.content.match(/\A\s*\n/)
      )
    ) && (
      pos = group.pos.content_match_as_pos(/\A[\[({](\s+)/, 1)
    )
      violates Rule::NoSpaceInsideBrackets, pos
    end

    # Check for unwanted space inside the closing bracket.
    last_term_pos = group.terms.last?.try(&.pos)
    if (
      last_term_pos &&
      group.pos.contains_on_last_line?(last_term_pos) &&
      !last_term_pos.content.match(/\n\s*\z/)
    ) && (
      pos = group.pos.content_match_as_pos(/(\s+)[\])}]\z/, 1)
    )
      violates Rule::NoSpaceInsideBrackets, pos
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

  # For all other nodes, we analyze nothing.
  def observe(ctx, node)
  end
end
