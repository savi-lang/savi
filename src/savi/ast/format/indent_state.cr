class Savi::AST::Format::IndentState
  class Layer
    property parent : Layer?
    property node : AST::Node
    property current_declare_indent : Int32
    property pos_list : Array({Source::Pos, Int32})?

    def initialize(@parent, @node, @current_declare_indent)
    end

    def empty?
      !@pos_list
    end

    def each_indent_pos
      @pos_list.try(&.each { |pos| yield pos })
    end

    def observe_indent_pos(pos, modifier)
      (@pos_list ||= [] of {Source::Pos, Int32}) << {pos, modifier}
    end

    def count_non_empty_layers
      self_count = empty? ? 0 : 1
      (@parent.try(&.count_non_empty_layers) || 0) + self_count
    end

    def resolve_indent_level
      @current_declare_indent + count_non_empty_layers - 1
    end
  end

  def initialize(package : Program::Package::Link, doc : AST::Document)
    @package = package
    @indent_stack = [Layer.new(nil, doc, 0)]
    @current_declare_indent = 0
    @next_indent_row = 0
    @indent_map = {} of Layer => Array({Source::Pos, Int32})
  end

  def visit_pre(ctx, visitor : Format, node : AST::Node)
    check_indent(ctx, node)
    maybe_push_indent(visitor, node)
  end

  def visit_post(ctx, visitor : Format, node : AST::Node)
    check_indent_post(ctx, node)
    maybe_pop_indent(visitor, node)
  end

  def maybe_push_indent(visitor, node)
    # A single-line node never adds to the indentation stack.
    return if node.pos.single_line?

    # Certain nodes are exempted from adding to the indentation stack.
    case node
    when AST::Document
      # Document nodes can never add indentation.
      return
    when AST::Group
      # Declare-level groups don't add indentation in this way.
      # Their indentation is already covered in the declare depth logic.
      return if node.style == ":"

      # Segments of pipe-delimited-groups don't add indentation either.
      # Their indentation is already covered by the parent group.
      return if node.style == "(" && (
        (parent = visitor.parent).is_a?(AST::Group) && parent.style == "|"
      )
    when AST::Relate
      # Certain Relate operators may add indentation; all others never do.
      return unless \
        case node.op.value
        when ".", "=", "<<=", "+=", "-=", ":"
          true
        else
          false
        end

      # Relate and Qualify nodes nested inside each other don't add indentation.
      return \
        if visitor.parent.is_a?(AST::Relate) \
        || visitor.parent.is_a?(AST::Qualify)
    when AST::Qualify
      # Relate and Qualify nodes nested inside each other don't add indentation.
      return \
        if visitor.parent.is_a?(AST::Relate) \
        || visitor.parent.is_a?(AST::Qualify)
    end

    # Push an indent stack layer for this node.
    @indent_stack << Layer.new(@indent_stack.last, node, @current_declare_indent)
  end

  def maybe_pop_indent(visitor, node)
    # Pop any indent stack layers associated with this node. It's done.
    while @indent_stack.last?.try(&.node) == node
      @indent_stack.pop
    end
  end

  def check_indent(ctx, node : AST::Node)
    # Declarations have a particular depth based on the contextual nesting
    # of the declarators that they were matched with, which informs the indent.
    if node.is_a?(AST::Declare) || (node.is_a?(AST::Group) && node.style == ":")
      @current_declare_indent = node.declare_depth
      @indent_stack << Layer.new(nil, node, @current_declare_indent)
    end

    # Don't check indentation for source rows we've already checked.
    return unless node.pos.row >= @next_indent_row

    # Check indent up until and including the row where this node begins.
    check_indent_up_to_here(node.pos.get_indent)
  end

  def check_indent_post(ctx, node : AST::Node)
    # Check indent up until and including the row where this node ends.
    check_indent_up_to_here(node.pos.get_finish_row_indent, outdent_final: true)
  end

  def check_indent_up_to_here(indent_pos : Source::Pos, outdent_final = false)
    # If we're already caught up to this row, then do nothing.
    return unless indent_pos.row >= @next_indent_row

    # Check each not-yet-checked row, going backwards, starting from the final.
    final_indent_pos = indent_pos
    seen_pipe = false
    while indent_pos.row >= @next_indent_row
      # If we see a row starting with the pipe character, then this row and all
      # continuing previous rows will be modified accordingly, because the pipe
      # character is a special case in indentation in pipe-delimited groups.
      seen_pipe = true if indent_pos.next_byte? == '|' && indent_pos.next_byte?(1) != '|'
      modifier =
        if outdent_final && final_indent_pos == indent_pos
          # If we've been asked to outdent the final row by one level,
          # and this happens to be the final row (the first one we check),
          # then modify the expected indent level by negative one.
          -1
        elsif seen_pipe
          # If we've seen a pipe character while we move backwards,
          # similarly modify the expected indent level by negative one.
          -1
        else
          # Otherwise, there is no modifier.
          0
        end

      # Assign this indent position and modifier into the mapping,
      # nested under the current indent stack layer.
      layer = @indent_stack.last
      layer.observe_indent_pos(indent_pos, modifier)
      (@indent_map[@indent_stack.last] ||= [] of {Source::Pos, Int32}) \
        << {indent_pos, modifier}

      # Move backward to the previous row in the source.
      indent_pos = indent_pos.get_prior_row_indent
      break unless indent_pos
    end

    # Finally, catch up our marker for how many rows we've already checked,
    # indicating the next row that should be checked as we move forward.
    @next_indent_row = final_indent_pos.row + 1
  end

  def each_indent_violation
    @indent_map.each { |layer, pos_list|
      next if layer.empty?

      expected_level = layer.resolve_indent_level

      layer.each_indent_pos { |pos, modifier|
        # Determine the individual expected level for this row
        # by applying the modifier that was stored alongside the row.
        individual_expected_level = expected_level + modifier

        # If the row has gone negative after the modifier, clip it to zero.
        if individual_expected_level < 0
          individual_expected_level = 0
        end

        # If the line ends immediately after the indentation,
        # there is trailing whitespace here which should be removed
        # by setting the individual expected level for this row to zero.
        case pos.next_byte?
        when '\n', '\r'
          individual_expected_level = 0
        end

        # TODO: if the indent_pos contains any tabs, it is a violation
        next if pos.size == individual_expected_level * 2

        # The correct indentation is two spaces per expected indentation level.
        yield ({pos, " " * (individual_expected_level * 2)})
      }
    }
  end
end
