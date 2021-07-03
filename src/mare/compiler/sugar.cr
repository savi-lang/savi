##
# The purpose of the Sugar pass is to expand universal shorthand forms,
# by filling in default ASTs where they are omitted, or transforming
# syntax sugar forms into their corresponding standard/canonical form,
# so that later passes can deal in less diverse, more predictable forms.
#
# This pass uses copy-on-mutate patterns to "mutate" the Program topology.
# This pass uses copy-on-mutate patterns to "mutate" the AST.
# This pass does not raise any compilation errors.
# This pass keeps temporary state at the per-function level.
# This pass produces no output state.
#
class Mare::Compiler::Sugar < Mare::AST::CopyOnMutateVisitor
  # TODO: Clean up, consolidate, and improve this caching mechanism.
  @@cache = {} of Program::Function::Link => {UInt64, Program::Function}
  def self.cached_or_run(l, t, f) : Program::Function
    f_link = f.make_link(t.make_link(l.make_link))
    input_hash = f.hash
    cache_result = @@cache[f_link]?
    cached_hash, cached_func = cache_result if cache_result
    return cached_func if cached_func && cached_hash == input_hash

    yield

    .tap do |result|
      @@cache[f_link] = {input_hash, result}
    end
  end

  def self.run(ctx, library)
    library.types_map_cow do |t|
      t.functions_map_cow do |f|
        cached_or_run library, t, f do
          sugar = new
          f = sugar.run(ctx, f)

          # Run pseudo-call transformation as a separate followup mini-pass,
          # because some of the sugar transformations need to already be done.
          PseudoCalls.run(ctx, f, sugar)
        end
      end
    end
  end

  def initialize
    @last_hygienic_local = 0
  end

  def next_local_name
    "hygienic_local.#{@last_hygienic_local += 1}"
  end

  def run(ctx, f)
    params = f.params
    ret = f.ret
    body = f.body

    # If any parameters contain assignments, convert them to defaults.
    if body && params
      params = params.dup if params.same?(f.params)
      params.terms = params.terms.map do |param|
        next param unless param.is_a?(AST::Relate) && param.op.value == "="

        AST::Relate.new(
          param.lhs,
          AST::Operator.new("DEFAULTPARAM").from(param.op),
          param.rhs,
        ).from(param)
      end
    end

    # Sugar the parameter signature and return type.
    params = params.try(&.accept(ctx, self))
    ret = ret.try(&.accept(ctx, self))

    # If any parameters contain assignables, make assignments in the body.
    if params
      param_assign_count = 0
      params = params.dup if params.same?(f.params)
      params.terms = params.terms.map_with_index do |param, index|
        # Dig through a default parameter value relation first if present.
        if param.is_a?(AST::Relate) && param.op.value == "DEFAULTPARAM"
          orig_param_with_default = param
          param = param.lhs
        end

        # If the param is a dot relation, treat it as an assignable.
        if param.is_a?(AST::Call)
          new_name = "ASSIGNPARAM.#{index + 1}"

          # Replace the parameter with our new name as the identifier.
          param_ident = AST::Identifier.new(new_name).from(param)
          if orig_param_with_default
            orig_param_with_default = AST::Relate.new(
              param_ident,
              orig_param_with_default.op,
              orig_param_with_default.rhs,
            ).from(orig_param_with_default)
          else
            assign_param = param_ident
          end

          # Add the assignment statement to the top of the function body.
          if body.nil?
            body = AST::Group.new(":").from(params)
          elsif body.same?(f.body)
            body = body.dup
            body.terms = body.terms.dup
          end
          body.terms.insert(param_assign_count,
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

        orig_param_with_default || assign_param || param
      end
    end

    # If this is a constructor, sugar a final "@" reference at the end.
    #
    # This isn't required by the CodeGen pass, but it improves intermediate
    # analysis such as the Classify value_needed? flag, since the final
    # expression in a constructor body isn't really used - "@" is returned.
    if f.has_tag?(:constructor) && body
      if body.same?(f.body)
        body = body.dup
        body.terms = body.terms.dup
      end
      body.terms << AST::Identifier.new("@").from(f.ident)
    end

    # If this is a behaviour or function that returns None,
    # sugar a final "None" reference at the end.
    if (f.has_tag?(:async) && !f.has_tag?(:constructor)) \
    || (ret.is_a?(AST::Identifier) && ret.value == "None")
      if body
        if body.same?(f.body)
          body = body.dup
          body.terms = body.terms.dup
        end
        body.terms << AST::Identifier.new("None").from(ret || f.ident)
      end
    end

    # Sugar the body.
    body = body.try { |body| body.accept(ctx, self) }

    unless params.same?(f.params) && ret.same?(f.ret) && body.same?(f.body)
      f = f.dup
      f.params = params
      f.ret = ret
      f.body = body
    end
    f
  end

  def visit(ctx, node : AST::Identifier)
    if node.value == "@"
      node
    elsif node.value.char_at(0) == '@'
      receiver_pos = node.pos.subset(0, node.pos.size - 1)
      ident_pos = node.pos.subset(1, 0)
      receiver = AST::Identifier.new("@").with_pos(receiver_pos)
      ident = AST::Identifier.new(node.value[1..-1]).with_pos(ident_pos)
      AST::Call.new(receiver, ident).from(node)
    elsif node.pos.source.pony?
      # PONY special case: uses the keyword `this` for the self value.
      if node.value == "this"
        AST::Identifier.new("@").from(node)
      # PONY special case: uses the keyword `error` for the error statement.
      elsif node.value == "error"
        AST::Jump.new(AST::Identifier.new("None").from(node), AST::Jump::Kind::Error).from(node)
      else
        node
      end
    else
      node
    end
  rescue exc : Exception
    raise Error.compiler_hole_at(node, exc)
  end

  # PONY special case: many operators have different names in Pony.
  def visit(ctx, node : AST::Operator)
    return node unless node.pos.source.pony?

    case node.value
    when "consume" then AST::Operator.new("--").from(node)
    when "and"     then AST::Operator.new("&&").from(node)
    when "or"      then AST::Operator.new("||").from(node)
    else node
    end
  rescue exc : Exception
    raise Error.compiler_hole_at(node, exc)
  end

  def visit(ctx, node : AST::Qualify)
    # Transform square-brace qualifications into method calls
    square_bracket =
      case node.group.style
      when "[" then "[]"
      when "[!" then "[]!"
      else
        nil
      end
    if square_bracket
      # PONY special case: square brackets are type params in Pony
      if node.pos.source.pony?
        term = node.term
        if term.is_a?(AST::Identifier) && term.value.match(/\A[A-Z]/)
          return AST::Qualify.new(
            term,
            AST::Group.new("(", node.group.terms.dup).from(node.group)
          ).from(node)
        else
          raise NotImplementedError.new(node.to_a.inspect)
        end
      end

      return visit(ctx,
        AST::Call.new(
          node.term,
          AST::Identifier.new(square_bracket).from(node.group),
          AST::Group.new("(", node.group.terms.dup).from(node.group),
        ).from(node)
      )
    end

    # If a call is the term of a qualify, move the qualification into call args.
    if (call = node.term).is_a?(AST::Call)
      args = node.group
      annotations = node.annotations
      node = AST::Call.new(
        call.receiver,
        call.ident,
        args,
      ).from(call)
      node.annotations = annotations

      # PONY special case: exclamation from args gets moved to the ident.
      if node.pos.source.pony? && args.style == "(!"
        new_ident_value = "#{node.ident.value}!"
        node.ident = AST::Identifier.new(new_ident_value).from(node.ident)
        args.style = "("
      end
    end

    node
  rescue exc : Exception
    raise Error.compiler_hole_at(node, exc)
  end

  def visit(ctx, node : AST::Prefix)
    case node.op.value
    when "!"
      visit(ctx,
        AST::Relate.new(
          AST::Identifier.new("False").from(node.op),
          AST::Operator.new("==").from(node.op),
          node.term,
        ).from(node)
      )
    else
      node
    end
  end

  def visit(ctx, node : AST::Relate)
    case node.op.value
    when "'", " ", "<:", "!<:", "===", "!==", "DEFAULTPARAM"
      node # skip these special-case operators
    when "."
      visit(ctx,
        AST::Call.new(node.lhs, node.rhs.as(AST::Identifier)).from(node)
      )
    when "->"
      if (call = node.lhs).is_a?(AST::Call)
        yield_params = nil
        yield_block = nil
        if (rhs = node.rhs).is_a?(AST::Group)
          if rhs.style == "("
            yield_block = rhs
          elsif rhs.style == "|" && rhs.terms.size == 2
            yield_params = rhs.terms.first.as(AST::Group)
            yield_block = rhs.terms.last.as(AST::Group)
          else
            ctx.error_at node.rhs, "This is invalid syntax for a yield block"
          end
        else
          ctx.error_at node.rhs, "This is invalid syntax for a yield block"
        end

        visit(ctx,
          AST::Call.new(
            call.receiver,
            call.ident,
            call.args,
            yield_params,
            yield_block,
          ).from(node)
        )
      else
        node
      end
    when "+=", "-="
      op =
        case node.op.value
        when "+=" then "+"
        when "-=" then "-"
        else raise NotImplementedError.new(node.op.value)
        end

      visit(ctx,
        AST::Relate.new(
          node.lhs,
          AST::Operator.new("=").from(node.op),
          visit(ctx,
            AST::Relate.new(
              node.lhs.dup,
              AST::Operator.new(op).from(node.op),
              node.rhs,
            ).from(node)
          )
        ).from(node)
      )
    when "=", "<<="
      lhs = node.lhs
      # If assigning to a ".identifier" relation, sugar as a "setter" call.
      if lhs.is_a?(AST::Call)
        base_name = lhs.ident.value
        suffix = ""
        if base_name.ends_with?("!")
          base_name = base_name[0...-1]
          suffix = "!"
        end
        name = "#{base_name}#{node.op.value}#{suffix}"
        ident = AST::Identifier.new(name).from(lhs.ident)
        args_list = [node.rhs]
        lhs.args.try { |lhs_args| args_list = lhs_args.terms + args_list }
        args = AST::Group.new("(", args_list).from(node.rhs)
        AST::Call.new(lhs.receiver, ident, args).from(node)
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
      args = AST::Group.new("(", [node.rhs]).from(node.rhs)
      AST::Call.new(node.lhs, ident, args).from(node)
    end
  rescue exc : Exception
    raise Error.compiler_hole_at(node, exc)
  end

  # Handle pseudo-method sugar like `as!` and `not!` calls.
  class PseudoCalls < Mare::AST::CopyOnMutateVisitor
    def self.run(ctx : Context, f : Program::Function, sugar : Sugar)
      ps = new(sugar)
      params = f.params.try(&.accept(ctx, ps))
      body = f.body.try(&.accept(ctx, ps))

      f = f.dup
      f.params = params
      f.body = body
      f
    end

    getter sugar : Sugar
    def initialize(@sugar)
    end

    def visit(ctx, node : AST::Node)
      return node unless node.is_a?(AST::Call)

      case node.ident.value
      when "as!", "not!"
        call_args = node.args
        Error.at node.ident,
          "This call requires exactly one argument (the type to check)" \
            unless call_args && call_args.terms.size == 1

        local_name = sugar.next_local_name
        type_arg = call_args.terms.first
        op =
          case node.ident.value
          when "as!" then "<:"
          when "not!" then "!<:"
          else raise NotImplementedError.new(node.ident)
          end

        group = AST::Group.new("(").from(node)
        group.terms << AST::Relate.new(
          AST::Identifier.new(local_name).from(node.receiver),
          AST::Operator.new("=").from(node.receiver),
          node.receiver,
        ).from(node.receiver)
        group.terms << AST::Choice.new([
          {
            AST::Relate.new(
              AST::Identifier.new(local_name).from(node.receiver),
              AST::Operator.new(op).from(node.ident),
              type_arg,
            ).from(node.ident),
            AST::Identifier.new(local_name).from(node.receiver),
          },
          {
            AST::Identifier.new("True").from(node.ident),
            AST::Jump.new(AST::Identifier.new("None").from(node), AST::Jump::Kind::Error).from(node.ident),
          },
        ] of {AST::Term, AST::Term}).from(node)

        group
      else
        node # all other calls are passed through unchanged
      end
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end
  end
end
