##
# The purpose of the Sugar pass is to expand universal shorthand forms,
# by filling in default ASTs where they are omitted, or transforming
# syntax sugar forms into their corresponding standard/canonical form,
# so that later passes can deal in less diverse, more predictable forms.
#
# This pass does not mutate the Program topology.
# This pass heavily mutates ASTs.
# This pass does not raise any compilation errors.
# This pass keeps temporary state at the per-function level.
# This pass produces no output state.
#
class Mare::Compiler::Sugar < Mare::AST::MutatingVisitor
  def self.run(ctx)
    ctx.program.types.each do |t|
      t.functions.each do |f|
        sugar = new
        sugar.run(f)

        # Run pseudo-call transformation as a separate followup mini-pass,
        # because some of the sugar transformations need to already be done.
        PseudoCalls.run(f, sugar)
      end
    end
  end

  def initialize
    @last_hygienic_local = 0
  end

  def next_local_name
    "hygienic_local.#{@last_hygienic_local += 1}"
  end

  def run(f)
    # If any parameters contain assignments, convert them to defaults.
    if f.body && f.params
      f.params.not_nil!.terms.each do |param|
        if param.is_a?(AST::Relate) && param.op.value == "="
          param.op.value = "DEFAULTPARAM"
        end
      end
    end

    # Sugar the parameter signature and return type.
    f.params.try(&.accept(self))
    f.ret.try(&.accept(self))

    # If any parameters contain assignables, make assignments in the body.
    if f.params
      param_assign_count = 0
      f.params.not_nil!.terms.each_with_index do |param, index|
        # Dig through a default parameter value relation first if present.
        if param.is_a?(AST::Relate) && param.op.value == "DEFAULTPARAM"
          orig_param_with_default = param
          param = param.lhs
        end

        # If the param is a dot relation, treat it as an assignable.
        if param.is_a?(AST::Relate) && param.op.value == "."
          new_name = "ASSIGNPARAM.#{index + 1}"

          # Replace the parameter with our new name as the identifier.
          param_ident = AST::Identifier.new(new_name).from(param)
          if orig_param_with_default
            orig_param_with_default.lhs = param_ident
          else
            f.params.not_nil!.terms[index] = param_ident
          end

          # Add the assignment statement to the top of the function body.
          f.body ||= AST::Group.new(":").from(f.params.not_nil!)
          f.body.not_nil!.terms.insert(param_assign_count,
            AST::Relate.new(
              param,
              AST::Operator.new("=").from(param),
              AST::Prefix.new(
                AST::Operator.new("--").from(param),
                param_ident.dup,
              ).from(param)
            ).from(param)
          )
          param_assign_count += 1
        end
      end
    end

    # If this is a constructor, sugar a final "@" reference at the end.
    #
    # This isn't required by the CodeGen pass, but it improves intermediate
    # analysis such as the Classify.value_needed? flag, since the final
    # expression in a constructor body isn't really used - "@" is returned.
    if f.has_tag?(:constructor)
      f.body.try { |body| body.terms << AST::Identifier.new("@").from(f.ident) }
    end

    # If this is a behaviour or function that returns None,
    # sugar a final "None" reference at the end.
    if (f.has_tag?(:async) && !f.has_tag?(:constructor)) \
    || ((ret = f.ret; ret.is_a?(AST::Identifier)) && ret.value == "None")
      f.body.try do |body|
        body.terms << AST::Identifier.new("None").from(ret || f.ident)
      end
    end

    # Sugar the body.
    f.body.try { |body| body.accept(self) }
  end

  def visit(node : AST::Identifier)
    if node.value == "@"
      node
    elsif node.value.char_at(0) == '@'
      lhs_pos = node.pos.subset(0, node.pos.size - 1)
      rhs_pos = node.pos.subset(1, 0)
      lhs = AST::Identifier.new("@").with_pos(lhs_pos)
      dot = AST::Operator.new(".").with_pos(lhs_pos)
      rhs = AST::Identifier.new(node.value[1..-1]).with_pos(rhs_pos)
      AST::Relate.new(lhs, dot, rhs).from(node)
    else
      node
    end
  end

  def visit(node : AST::Qualify)
    # Transform square-brace qualifications into method calls
    square_bracket =
      case node.group.style
      when "[" then "[]"
      when "[!" then "[]!"
      end
    if square_bracket
      lhs = node.term
      node.term = AST::Identifier.new(square_bracket).from(node.group)
      args = node.group.tap { |n| n.style = "(" }
      dot = AST::Operator.new(".").from(node.group)
      rhs = visit(node)
      return AST::Relate.new(lhs, dot, rhs).from(node)
    end

    # If a dot relation is within a qualify, move the qualify into the
    # right-hand-side of the dot (this cleans up the work of the parser).
    new_top = nil
    while (dot = node.term).is_a?(AST::Relate) && dot.op.value == "."
      node.term = dot.rhs
      dot.rhs = node
      new_top ||= dot
    end
    new_top || node
  end

  def visit(node : AST::Relate)
    case node.op.value
    when ".", "'", "+>", " ", "<:", "is", "DEFAULTPARAM"
      node # skip these special-case operators
    when "->"
      # If a dot relation is within this (which doesn't happen in the parser,
      # but may happen artifically such as the `@identifier` sugar above),
      # then always move the qualify into the right-hand-side of the dot.
      new_top = nil
      while (dot = node.lhs).is_a?(AST::Relate) && dot.op.value == "."
        node.lhs = dot.rhs
        dot.rhs = node
        new_top ||= dot
      end
      new_top || node
    when "+=", "-="
      op =
        case node.op.value
        when "+=" then "+"
        when "-=" then "-"
        else raise NotImplementedError.new(node.op.value)
        end

      visit(
        AST::Relate.new(
          node.lhs,
          AST::Operator.new("=").from(node.op),
          visit(
            AST::Relate.new(
              node.lhs.dup,
              AST::Operator.new(op).from(node.op),
              node.rhs,
            ).from(node)
          )
        ).from(node)
      )
    when "="
      # If assigning to a ".[identifier]" relation, sugar as a "setter" method.
      lhs = node.lhs
      if lhs.is_a?(AST::Relate) \
      && lhs.op.value == "." \
      && lhs.rhs.is_a?(AST::Identifier)
        name = "#{lhs.rhs.as(AST::Identifier).value}="
        ident = AST::Identifier.new(name).from(lhs.rhs)
        args = AST::Group.new("(", [node.rhs]).from(node.rhs)
        rhs = AST::Qualify.new(ident, args).from(node)
        AST::Relate.new(lhs.lhs, lhs.op, rhs).from(node)
      # If assigning to a ".[]" relation, sugar as an "element setter" method.
      elsif lhs.is_a?(AST::Relate) \
      && lhs.op.value == "." \
      && lhs.rhs.is_a?(AST::Qualify) \
      && lhs.rhs.as(AST::Qualify).term.is_a?(AST::Identifier) \
      && lhs.rhs.as(AST::Qualify).term.as(AST::Identifier).value == "[]"
        inner = lhs.rhs.as(AST::Qualify)
        ident = AST::Identifier.new("[]=").from(inner.term)
        args = inner.group
        args.terms << node.rhs
        rhs = AST::Qualify.new(ident, args).from(node)
        AST::Relate.new(lhs.lhs, lhs.op, rhs).from(node)
      # If assigning to a ".[]!" relation, sugar as an "element setter" method.
      elsif lhs.is_a?(AST::Relate) \
      && lhs.op.value == "." \
      && lhs.rhs.is_a?(AST::Qualify) \
      && lhs.rhs.as(AST::Qualify).term.is_a?(AST::Identifier) \
      && lhs.rhs.as(AST::Qualify).term.as(AST::Identifier).value == "[]!"
        inner = lhs.rhs.as(AST::Qualify)
        ident = AST::Identifier.new("[]=!").from(inner.term)
        args = inner.group
        args.terms << node.rhs
        rhs = AST::Qualify.new(ident, args).from(node)
        AST::Relate.new(lhs.lhs, lhs.op, rhs).from(node)
      else
        node
      end
    when "&&"
      # Convert into a choice modeling a short-circuiting logical "AND".
      # Create a choice that executes and returns the rhs expression
      # if the lhs expression is True, and otherwise returns False.
      AST::Choice.new([
        {node.lhs, node.rhs},
        {AST::Identifier.new("True").from(node.op),
          AST::Identifier.new("False").from(node.op)},
      ]).from(node.op)
    when "||"
      # Convert into a choice modeling a short-circuiting logical "OR".
      # Create a choice that returns True if the lhs expression is True,
      # and otherwise executes and returns the rhs expression.
      AST::Choice.new([
        {node.lhs, AST::Identifier.new("True").from(node.op)},
        {AST::Identifier.new("True").from(node.op), node.rhs},
      ]).from(node.op)
    else
      # Convert the operator relation into a single-argument method call.
      ident = AST::Identifier.new(node.op.value).from(node.op)
      dot = AST::Operator.new(".").from(node.op)
      args = AST::Group.new("(", [node.rhs]).from(node.rhs)
      rhs = AST::Qualify.new(ident, args).from(node)
      AST::Relate.new(node.lhs, dot, rhs).from(node)
    end
  end

  # Handle pseudo-method sugar like `as!` calls.
  # TODO: Can this be done as a "universal method" rather than sugar?
  class PseudoCalls < Mare::AST::MutatingVisitor
    def self.run(f : Program::Function, sugar : Sugar)
      ps = new(sugar)
      f.params.try(&.accept(ps))
      f.body.try(&.accept(ps))
    end

    getter sugar : Sugar
    def initialize(@sugar)
    end

    def visit(node : AST::Node)
      return node unless node.is_a?(AST::Relate) && node.op.value == "."

      call_ident, call_args, yield_params, yield_block = AST::Extract.call(node)

      return node unless call_ident

      case call_ident.value
      when "as!"
        Error.at call_ident,
          "This call requires exactly one argument (the type to check)" \
            unless call_args && call_args.terms.size == 1

        local_name = sugar.next_local_name
        type_arg = call_args.terms.first

        group = AST::Group.new("(").from(node)
        group.terms << AST::Relate.new(
          AST::Identifier.new(local_name).from(node.lhs),
          AST::Operator.new("=").from(node.lhs),
          node.lhs,
        ).from(node.lhs)
        group.terms << AST::Choice.new([
          {
            AST::Relate.new(
              AST::Identifier.new(local_name).from(node.lhs),
              AST::Operator.new("<:").from(call_ident),
              type_arg,
            ).from(call_ident),
            AST::Identifier.new(local_name).from(node.lhs),
          },
          {
            AST::Identifier.new("True").from(call_ident),
            AST::Identifier.new("error!").from(call_ident),
          },
        ] of {AST::Term, AST::Term}).from(node.op)

        group
      else
        node # all other calls are passed through unchanged
      end
    end
  end
end
