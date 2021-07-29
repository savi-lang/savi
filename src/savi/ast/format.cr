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
  end

  def violates(rule, pos, replacement = "")
    @edits << Edit.new(rule, pos, replacement)
  end

  def visit(ctx, group : AST::Group)
    return if group.style == " " # no analysis for whitespace-style groups

    group.terms.each_with_index { |term, index|
      term_pos = term.span_pos
      next_term_pos = group.terms[index + 1]?.try(&.span_pos)

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
  def visit(ctx, node)
  end
end
