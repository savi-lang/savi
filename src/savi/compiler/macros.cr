##
# The purpose of the Macros pass is to parse and expand semantic forms that
# may be more context-sensitive/dynamic than those parsed in the parser itself.
# Eventually we wish to allow the user code to register this macro logic in the
# earlier passes of evaluation in the compiler, to make them fully dynamic.
# This is not possible yet, as all macros are hard-coded here in the compiler.
#
# This pass uses copy-on-mutate patterns to "mutate" the Program topology.
# This pass uses copy-on-mutate patterns to "mutate" the AST.
# This pass may raise a compilation error.
# This pass keeps temporary state at the per-function level.
# This pass produces no output state.
#
class Savi::Compiler::Macros < Savi::AST::CopyOnMutateVisitor
  # TODO: This class should interpret macro declarations by the user and treat
  # those the same as macro declarations in core Savi, with both getting
  # executed here dynamically instead of declared here statically.

  # TODO: Clean up, consolidate, and improve this caching mechanism.
  @@cache = {} of Program::Function::Link => {UInt64, Program::Function}
  def self.cached_or_run(ctx, l, t, f) : Program::Function
    f_link = f.make_link(t.make_link(l.make_link))
    input_hash = f.hash
    cache_result = @@cache[f_link]?
    cached_hash, cached_func = cache_result if cache_result
    return cached_func if cached_func && cached_hash == input_hash

    puts "    RERUN . #{self} #{f_link.show}" if cache_result && ctx.options.print_perf

    yield

    .tap do |result|
      @@cache[f_link] = {input_hash, result}
    end
  end

  def self.run(ctx, package)
    package.types_map_cow do |t|
      t.functions_map_cow do |f|
        cached_or_run ctx, package, t, f do
          macros = new(f)
          macros.maybe_compiler_intrinsic
          f = macros.run(ctx)

          f = SimpleIdentifiers.run(ctx, f, macros)
        end
      end
    end
  end

  getter func
  def initialize(@func : Program::Function)
    @last_hygienic_local = 0
  end

  def next_local_name
    "hygienic_macros_local.#{@last_hygienic_local += 1}"
  end

  def run(ctx)
    @func = @func.accept(ctx, self)
    @func
  end

  def maybe_compiler_intrinsic
    body = @func.body
    return unless \
      body.is_a?(AST::Group) &&
      body.style == ":" &&
      body.terms.size == 1

    group = body.terms[0]
    return unless \
      group.is_a?(AST::Group) &&
      group.style == " " &&
      group.terms.size == 2 &&
      Util.match_ident?(group, 0, "compiler") &&
      Util.match_ident?(group, 1, "intrinsic")

    # Having confirmed that the function body contains only the phrase
    # 'compiler intrinsic' as a macro-like form, we can tag it and delete it.
    @func = @func.dup
    @func.body = nil
    @func.add_tag(:compiler_intrinsic)
  end

  def visit_pre(ctx, node : AST::Group)
    # Handle only groups that are whitespace-delimited, as these are the only
    # groups that we may match and interpret as if they are macros.
    return node unless node.style == " "

    if Util.match_ident?(node, 0, "if")
      Util.require_terms(node, [
        nil,
        "the condition to be satisfied",
        "the body to be conditionally executed,\n" \
        "  including an optional else clause partitioned by `|`",
      ])
      visit_if(node)
    elsif Util.match_ident?(node, 0, "while")
      Util.require_terms(node, [
        nil,
        "the condition to be satisfied",
        "the body to be conditionally executed in a loop,\n" \
        "  including an optional else clause partitioned by `|`",
      ])
      visit_while(node)
    elsif Util.match_ident?(node, 0, "case")
      Util.require_terms(node, [
        nil,
        "the group of cases to check, partitioned by `|`",
      ])
      visit_case(node)
    elsif Util.match_ident?(node, 0, "try")
      Util.require_terms(node, [
        nil,
        "the body to be attempted, followed by an optional\n" \
        "  else clause to execute if the body errors (partitioned by `|`)",
      ])
      visit_try(node)
    elsif Util.match_ident?(node, 0, "yield")
      visit_yield(node)
    elsif Util.match_ident?(node, 0, "return")
      visit_jump(node, AST::Jump::Kind::Return)
    elsif Util.match_ident?(node, 0, "error!")
      visit_jump(node, AST::Jump::Kind::Error)
    elsif Util.match_ident?(node, 0, "break")
      visit_jump(node, AST::Jump::Kind::Break)
    elsif Util.match_ident?(node, 0, "next")
      visit_jump(node, AST::Jump::Kind::Next)
    elsif Util.match_ident?(node, 0, "source_code_position_of_argument")
      Util.require_terms(node, [
        nil,
        "the parameter whose argument source code should be captured",
      ])
      visit_source_code_position_of_argument(node)
    elsif Util.match_ident?(node, 0, "stack_address_of_variable")
      Util.require_terms(node, [
        nil,
        "the local variable whose stack address should be captured",
      ])
      visit_stack_address_of_variable(node)
    elsif Util.match_ident?(node, 0, "static_address_of_function")
      Util.require_terms(node, [
        nil,
        "the function whose static address should be captured",
      ])
      visit_static_address_of_function(node)
    elsif Util.match_ident?(node, 0, "reflection_of_type")
      Util.require_terms(node, [
        nil,
        "the reference whose compile-time type is to be reflected",
      ])
      visit_reflection_of_type(node)
    elsif Util.match_ident?(node, 0, "reflection_of_runtime_type_name")
      Util.require_terms(node, [
        nil,
        "the reference whose type name is to be reflected at runtime",
      ])
      visit_reflection_of_runtime_type_name(node)
    elsif Util.match_ident?(node, 0, "identity_digest_of")
      Util.require_terms(node, [
        nil,
        "the value whose identity is to be hashed",
      ])
      visit_identity_digest_of(node)
    else
      node
    end
  rescue exc : Exception
    raise exc if exc.is_a?(Error) # TODO: ctx.errors multi-error capability
    raise Error.compiler_hole_at(node, exc)
  end

  def visit_pre(ctx, node : AST::Call)
    case node.ident.value
    when "as!", "not!"
      call_args = node.args
      Error.at node.ident,
        "This call requires exactly one argument (the type to check)" \
          unless call_args && call_args.terms.size == 1

      local_name = next_local_name
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
    raise exc if exc.is_a?(Error) # TODO: ctx.errors multi-error capability
    raise Error.compiler_hole_at(node, exc)
  end

  def visit_pre(ctx, node : AST::Relate)
    lhs = node.lhs

    if lhs.is_a?(AST::Group) && lhs.style == " " && Util.match_ident?(lhs, 0, "case")
      term = lhs.terms[1]
      Error.at term,
        "Expected this term to not be a parenthesized group" \
          if term.is_a?(AST::Group) && (term.style == "(" || term.style == "|")

      group = node.rhs
      Error.at group,
        "Expected this term to be a parenthesized group of cases to check,\n" \
        "  partitioned into sections by `|`, in which each body section\n" \
        "  is preceded by a condition section to be evaluated as a Bool,\n" \
        "  with an optional else body section at the end" \
          unless group.is_a?(AST::Group) && group.style == "|"

      visit_case(node)
    elsif lhs.is_a?(AST::Identifier) && lhs.value == "assert" && node.op.value == ":"
      visit_assert(node, node.rhs)
    elsif node.op.value == ":" &&
          lhs.is_a?(AST::Group) &&
          lhs.style == " " &&
          Util.match_ident?(lhs, 0, "assert") &&
          Util.match_ident?(lhs, 1, "no_error")
      visit_assert_no_error(node, node.rhs)
    elsif node.op.value == ":" &&
          lhs.is_a?(AST::Group) &&
          lhs.style == " " &&
          Util.match_ident?(lhs, 0, "assert") &&
          Util.match_ident?(lhs, 1, "error")
      visit_assert_error(node, node.rhs)
    else
      node
    end
  rescue exc : Exception
    raise exc if exc.is_a?(Error) # TODO: ctx.errors multi-error capability
    raise Error.compiler_hole_at(node, exc)
  end

  def visit_pre(ctx, node : AST::ComposeString)
    # Because we have hygienic locals to set up, we have to run a sequence.
    # The final expression of the sequence will be the actual string expression.
    sequence = AST::Group.new("(").from(node)

    # Use a hygienic local for each non-literal part of the composed string.
    # The literal parts don't need a hygienic local because they are static.
    parts = node.terms.map { |term|
      if term.is_a? AST::LiteralString
        term
      else
        local = AST::Identifier.new(next_local_name).from(term)
        local_assign = AST::Relate.new(
          AST::Relate.new(
            local,
            AST::Operator.new("EXPLICITTYPE").from(term),
            AST::Identifier.new("box").from(term),
          ).from(term),
          AST::Operator.new("=").from(term),
          term,
        ).from(term)
        sequence.terms << local_assign
        local
      end
    }

    # Add up the total space requested by each part, as an additive expression.
    # We start with `USize.zero`, then chain `+ part.into_string_space` calls
    # for each part in the composed string until we have the entire sum.
    space_expr = AST::Call.new(
      AST::Identifier.new("USize").from(node),
      AST::Identifier.new("zero").from(node),
    ).from(node)
    parts.each { |part|
      space_expr = AST::Call.new(
        space_expr,
        AST::Identifier.new("+").from(node),
        AST::Group.new("(", [
          AST::Call.new(
            part,
            AST::Identifier.new("into_string_space").from(part)
          ).from(part),
        ] of AST::Node).from(part),
      ).from(node)
    }

    # Call each part's `into_string` method, passing the result of the previous
    # part as the argument. The argument for the first call is `String.new_iso`
    # with the space expression as its argument to allocate the requested space.
    # The hope is that if the correct amount of space was requested, we won't
    # need to re-allocate the string as its size grows (if its `space >= size`).
    string_expr = AST::Call.new(
      AST::Identifier.new("String").from(node),
      AST::Identifier.new("new_iso").from(node),
      AST::Group.new("(", [space_expr] of AST::Node).from(node),
    ).from(node)
    parts.each { |part|
      string_expr = AST::Call.new(
        part,
        AST::Identifier.new("into_string").from(part),
        AST::Group.new("(", [string_expr] of AST::Node).from(part),
      ).from(part)
    }

    # Add the string expression to the sequence of terms.
    # This is the final expression in the sequence, so it will
    # be the result of the sequence when we return the sequence.
    sequence.terms << string_expr
    sequence

  rescue exc : Exception
    raise exc if exc.is_a?(Error) # TODO: ctx.errors multi-error capability
    raise Error.compiler_hole_at(node, exc)
  end

  def visit_if(node : AST::Group)
    orig = node.terms[0]
    cond = node.terms[1]
    body = node.terms[2]

    if body.is_a?(AST::Group) && body.style == "|"
      Util.require_terms(body, [
        "the body to be executed when the condition is true",
        "the body to be executed otherwise (the \"else\" case)",
      ], true)

      clauses = [
        {cond, body.terms[0]},
        {AST::Identifier.new("True").from(orig), body.terms[1]},
      ]
    else
      clauses = [{cond, body}]

      # Create an implicit else clause that covers all remaining cases.
      # TODO: add a pass to detect a Choice that doesn't have this,
      # or maybe implicitly assume it later without adding it to the AST?
      clauses << {
        AST::Identifier.new("True").from(orig),
        AST::Identifier.new("None").from(orig),
      }
    end

    AST::Group.new("(", [
      AST::Choice.new(clauses).from(orig),
    ] of AST::Term).from(node)
  end

  def visit_while(node : AST::Group)
    orig = node.terms[0]
    initial_cond = node.terms[1]
    body = node.terms[2]
    repeat_cond = node.terms[1] # same as initial_cond
    else_body = nil

    if body.is_a?(AST::Group) && body.style == "|"
      Util.require_terms(body, [
        "the body to be executed on loop when the condition is true",
        "the body to be executed otherwise (the \"else\" case)",
      ], true)

      else_body = body.terms[1]
      body      = body.terms[0]
    end

    else_body ||= AST::Identifier.new("None").from(node)

    AST::Group.new("(", [
      AST::Loop.new(initial_cond, body, repeat_cond, else_body).from(orig),
    ] of AST::Term).from(node)
  end

  def visit_case(node : AST::Group)
    orig = node.terms[0]
    group = node.terms[1]

    Error.at group,
      "Expected this term to be a parenthesized group of cases to check,\n" \
      "  partitioned into sections by `|`, in which each body section\n" \
      "  is preceded by a condition section to be evaluated as a Bool,\n" \
      "  with an optional else body section at the end" \
        unless group.is_a?(AST::Group) && group.style == "|"

    # By construction, every term in a `|` group must be a `(` group.
    sections = group.as(AST::Group).terms.map(&.as(AST::Group))

    # Discard an empty section at the beginning if present.
    # This gives aesthetic alternatives for single vs multi-line renderings.
    sections.shift if sections.first.terms.empty?

    # Add a condition and case body for each pair of sections we encounter.
    clauses = [] of {AST::Term, AST::Term}
    while sections.size >= 2
      cond = sections.shift
      body = sections.shift
      clauses << {cond, body}
    end

    # Add an else case at the end. This has an implicit value of None,
    # unless the number of total sections was odd, in which case the last
    # section is counted as being the body to execute in the else case.
    # TODO: add a pass to detect a Choice that doesn't have this,
    # or maybe implicitly assume it later without adding it to the AST?
    clauses << {
      AST::Identifier.new("True").from(orig),
      sections.empty? ? AST::Identifier.new("None").from(orig) : sections.pop
    }

    AST::Group.new("(", [
      AST::Choice.new(clauses).from(orig),
    ] of AST::Term).from(node)
  end

  def visit_case(node : AST::Relate)
    term = node.lhs.as(AST::Group).terms[1]
    op = node.op
    group = node.rhs.as(AST::Group)
    orig = group.terms[0]

    # If the term is not a simple identifier, use a hygienic local to \
    # hold the value resulting from the term so that we can refer to it
    # multiple times without evaluating the term expression again.
    if !term.is_a?(AST::Identifier)
      local_name = next_local_name
      local = AST::Identifier.new(local_name).from(term)
      local_assign = AST::Relate.new(
        local,
        AST::Operator.new("=").from(term),
        term,
      ).from(term)
    end

    # By construction, every term in a `|` group must be a `(` group.
    sections = group.terms.map(&.as(AST::Group))

    # Discard an empty section at the beginning if present.
    # This gives aesthetic alternatives for single vs multi-line renderings.
    sections.shift if sections.first.terms.empty?

    # Add a condition and case body for each pair of sections we encounter.
    # Clauses are constructed as a new Relate node using the hygienic local
    # operation, plus the body in each even section.
    clauses = [] of {AST::Term, AST::Term}
    while sections.size >= 2
      cond = sections.shift
      body = sections.shift
      lhs = (local || term).dup
      relate = AST::Relate.new(lhs, op, cond.terms[0]).from(cond)
      clauses << {
        AST::Group.new("(", [relate] of AST::Term).from(cond),
        body
      }
    end

    # Add an else case at the end. This has an implicit value of None,
    # unless the number of total sections was odd, in which case the last
    # section is counted as being the body to execute in the else case.
    # TODO: add a pass to detect a Choice that doesn't have this,
    # or maybe implicitly assume it later without adding it to the AST?
    clauses << {
      AST::Identifier.new("True").from(orig),
      sections.empty? ? AST::Identifier.new("None").from(orig) : sections.pop
    }

    choice = AST::Choice.new(clauses).from(node)
    AST::Group.new("(",
      local_assign ? [local_assign, choice] : [choice] of AST::Node
    ).from(node)
  end

  def visit_try(node : AST::Group)
    orig = node.terms[0]
    body = node.terms[1]
    else_body = nil

    if body.is_a?(AST::Group) && body.style == "|"
      Util.require_terms(body, [
        "the body to attempt to execute fully",
        "the body to be executed if the previous errored (the \"else\" case)",
      ], true)

      else_body = body.terms[1]
      body      = body.terms[0]
    end

    else_body ||= AST::Identifier.new("None").from(node)

    AST::Group.new("(", [
      AST::Try.new(body, else_body).from(orig),
    ] of AST::Term).from(node)
  end

  def visit_yield(node : AST::Group)
    if Util.match_ident?(node, 2, "if")
      Util.require_terms(node, [
        nil,
        "the value to be yielded out to the calling function",
        nil,
        "the condition that causes it to yield",
      ])
      visit_conditional_yield(node, cond: node.terms[3])
    elsif Util.match_ident?(node, 2, "unless")
      Util.require_terms(node, [
        nil,
        "the value to be yielded out to the calling function",
        nil,
        "the condition that prevents it from yielding",
      ])
      visit_conditional_yield(node, cond: node.terms[3], negate: true)
    else
      Util.require_terms(node, [
        nil,
        "the value to be yielded out to the calling function",
      ])
      visit_unconditional_yield(node)
    end
  end

  def visit_unconditional_yield(node : AST::Group)
    orig = node.terms[0]
    term = node.terms[1]

    terms =
      if term.is_a?(AST::Group) && term.style == "("
        term.terms
      else
        [term]
      end

    AST::Group.new("(", [
      AST::Yield.new(terms).from(orig),
    ] of AST::Term).from(node)
  end

  def visit_conditional_yield(
    node : AST::Group,
    cond : AST::Term,
    negate : Bool = false,
  )
    orig = node.terms[0]
    term = node.terms[1]

    terms =
      if term.is_a?(AST::Group) && term.style == "("
        term.terms
      else
        [term]
      end

    yield_node = AST::Yield.new(terms).from(orig)
    none = AST::Identifier.new("None").from(node)

    AST::Group.new("(", [
      AST::Choice.new([
        {cond,                                   negate ? none : yield_node},
        {AST::Identifier.new("True").from(node), negate ? yield_node : none},
      ]).from(orig),
    ] of AST::Term).from(node)
  end

  def visit_jump(node : AST::Group, kind : AST::Jump::Kind)
    ing_word, describe_action, describe_value =
      case kind
      when AST::Jump::Kind::Return
        {"returning", "return early", "value to return"}
      when AST::Jump::Kind::Error
        {"raising", "raise an error", "error value to raise"}
      when AST::Jump::Kind::Break
        {"breaking", "break the iteration", "result value to break iteration with"}
      when AST::Jump::Kind::Next
        {"skipping", "skip to the next iteration", "value to finish this block with"}
      else
        raise NotImplementedError.new(kind)
      end
    describe_action_ing = describe_action.sub(/\w+/, ing_word)

    if Util.match_ident?(node, 1, "if")
      Util.require_terms(node, [
        nil,
        nil,
        "the condition that causes it to #{describe_action}",
      ])
      visit_conditional_jump(node, kind, cond: node.terms[2])
    elsif Util.match_ident?(node, 1, "unless")
      Util.require_terms(node, [
        nil,
        nil,
        "the condition that prevents it from #{describe_action_ing}",
      ])
      visit_conditional_jump(node, kind, cond: node.terms[2], negate: true)
    elsif Util.match_ident?(node, 2, "if")
      Util.require_terms(node, [
        nil,
        "the #{describe_value}",
        nil,
        "the condition that causes it to #{describe_action}",
      ])
      visit_conditional_jump(node, kind, term: node.terms[1], cond: node.terms[3])
    elsif Util.match_ident?(node, 2, "unless")
      Util.require_terms(node, [
        nil,
        "the #{describe_value}",
        nil,
        "the condition that prevents it from #{describe_action_ing}",
      ])
      visit_conditional_jump(node, kind, term: node.terms[1], cond: node.terms[3], negate: true)
    else
      Util.require_terms(node, [
        nil,
        "the #{describe_value}",
      ])
      visit_unconditional_jump(node, kind)
    end
  end

  def visit_unconditional_jump(node : AST::Group, kind : AST::Jump::Kind)
    orig = node.terms[0]
    term = node.terms[1]

    AST::Group.new("(", [
      AST::Jump.new(term, kind).from(orig)
    ] of AST::Term).from(node)
  end

  def visit_conditional_jump(
    node : AST::Group,
    kind : AST::Jump::Kind,
    cond : AST::Term,
    term : AST::Term? = nil,
    negate : Bool = false,
  )
    orig = node.terms[0]
    term ||= AST::Identifier.new("None").from(orig)

    jump = AST::Jump.new(term, kind).from(orig)
    none = AST::Identifier.new("None").from(node)

    AST::Group.new("(", [
      AST::Choice.new([
        {cond,                                   negate ? none : jump},
        {AST::Identifier.new("True").from(node), negate ? jump : none},
      ]).from(orig),
    ] of AST::Term).from(node)
  end

  # The `visit_assert` methods compiles different forms of the `assert` macro.
  # The expression to evaluate is the `rhs` of the `assert: expr` Relate node.
  #
  # When the expression itself contains operators it will compile into `Spec.Assert.relation`.
  #
  # assert: True == True
  # assert: foo || bar && baz
  #
  # When the relation uses the `<:` and `!<:` operator the assert is compiled into a special
  # `Spec.Assert.type_relation` method.
  #
  # When the expression is any other kind of node it will compile into a `Spec.Assert.condition`.
  #
  # assert: True
  # assert: Something.foo
  #
  def visit_assert(node : AST::Relate, expr : AST::Relate)
    orig = node.lhs.as(AST::Identifier)
    lhs = expr.lhs
    op = expr.op
    rhs = expr.rhs

    # For the case where `rhs` is not a value expression, but rather a type expression:
    # `String`, `Array(String)` or `(String | None)`, we will compile into the
    # `Spec.Assert.type_relation` call.
    return visit_assert_type_relation(node, expr) if op.value == "<:" || op.value == "!<:"

    # Use a hygienic local to explicitly hold the expressions as box.
    # This also helps to refer to them multiple times without evaluating them again.
    local_lhs = AST::Identifier.new(next_local_name).from(lhs)
    local_lhs_box = AST::Relate.new(
      local_lhs,
      AST::Operator.new("EXPLICITTYPE").from(lhs),
      AST::Identifier.new("box").from(lhs),
    ).from(lhs)
    local_lhs_assign = AST::Relate.new(
      local_lhs_box,
      AST::Operator.new("=").from(lhs),
      lhs,
    ).from(lhs)

    local_rhs = AST::Identifier.new(next_local_name).from(rhs)
    local_rhs_box = AST::Relate.new(
      local_rhs,
      AST::Operator.new("EXPLICITTYPE").from(rhs),
      AST::Identifier.new("box").from(rhs),
    ).from(rhs)
    local_rhs_assign = AST::Relate.new(
      local_rhs_box,
      AST::Operator.new("=").from(rhs),
      rhs,
    ).from(rhs)

    relate = AST::Relate.new(
      local_lhs,
      op,
      local_rhs,
    ).from(expr)

    call = AST::Call.new(
      AST::Identifier.new("Spec.Assert").from(orig),
      AST::Identifier.new("relation").from(orig),
      AST::Group.new("(", [
        AST::Identifier.new("@").from(node),
        AST::LiteralString.new(op.value).from(op),
        local_lhs,
        local_rhs,
        relate,
      ] of AST::Term).from(expr)
    ).from(orig)

    try = AST::Try.new(
      AST::Group.new("(", [
        local_lhs_assign,
        local_rhs_assign,
        call,
      ] of AST::Term).from(orig),
      AST::Group.new("(", [
        AST::Call.new(
          AST::Identifier.new("Spec.Assert").from(expr),
          AST::Identifier.new("has_error").from(expr),
          AST::Group.new("(", [
            AST::Identifier.new("@").from(node),
            AST::Identifier.new("True").from(node),
            AST::Identifier.new("False").from(node),
          ] of AST::Term).from(expr)
        ).from(expr),
      ] of AST::Term).from(orig),
      allow_non_partial_body: true,
    ).from(node)

    AST::Group.new("(", [try] of AST::Term).from(node)
  end

  def visit_assert_type_relation(node : AST::Relate, expr : AST::Relate)
    orig = node.lhs.as(AST::Identifier)
    lhs = expr.lhs
    op = expr.op
    rhs = expr.rhs

    # Use a hygienic local to refer to it multiple times without evaluating again.
    local_lhs_name = AST::Identifier.new(next_local_name).from(lhs)
    local_lhs = AST::Relate.new(
      local_lhs_name,
      AST::Operator.new("=").from(lhs),
      lhs,
    ).from(lhs)

    local_relate_name = AST::Identifier.new(next_local_name).from(expr)
    local_relate = AST::Relate.new(
      local_relate_name,
      AST::Operator.new("=").from(expr),
      AST::Relate.new(
        local_lhs_name,
        op,
        rhs,
      ).from(expr)
    ).from(expr)

    call = AST::Call.new(
      AST::Identifier.new("Spec.Assert").from(orig),
      AST::Identifier.new("type_relation").from(orig),
      AST::Group.new("(", [
        AST::Identifier.new("@").from(node),
        AST::LiteralString.new(op.value).from(op),
        AST::Prefix.new(
          AST::Operator.new("--").from(expr),
          local_lhs_name
        ).from(lhs),
        AST::LiteralString.new(rhs.pos.content).from(rhs),
        local_relate_name,
      ] of AST::Term).from(expr)
    ).from(orig)

    try = AST::Try.new(
      AST::Group.new("(", [
        local_lhs,
        local_relate,
        call,
      ] of AST::Term).from(orig),
      AST::Group.new("(", [
        AST::Call.new(
          AST::Identifier.new("Spec.Assert").from(expr),
          AST::Identifier.new("has_error").from(expr),
          AST::Group.new("(", [
            AST::Identifier.new("@").from(node),
            AST::Identifier.new("True").from(node),
            AST::Identifier.new("False").from(node),
          ] of AST::Term).from(expr)
        ).from(expr),
      ] of AST::Term).from(orig),
      allow_non_partial_body: true,
    ).from(node)

    AST::Group.new("(", [try] of AST::Term).from(node)
  end

  def visit_assert(node : AST::Relate, expr : AST::Node)
    orig = node.lhs.as(AST::Identifier)

    # We're re-writing the code to wrap it all with try
    #
    # try (
    #   Spec.Assert.condition(@, expr)
    # |
    #   Spec.Assert.has_error(@, True, False) // Booleans mean "has error" and "expected error?"
    # )
    #
    try = AST::Try.new(
      AST::Group.new("(", [
        AST::Call.new(
          AST::Identifier.new("Spec.Assert").from(expr),
          AST::Identifier.new("condition").from(expr),
          AST::Group.new("(", [
            AST::Identifier.new("@").from(node),
            expr,
          ] of AST::Term).from(expr)
        ).from(expr),
      ] of AST::Term).from(orig),
      AST::Group.new("(", [
        AST::Call.new(
          AST::Identifier.new("Spec.Assert").from(expr),
          AST::Identifier.new("has_error").from(expr),
          AST::Group.new("(", [
            AST::Identifier.new("@").from(node),
            AST::Identifier.new("True").from(node),
            AST::Identifier.new("False").from(node),
          ] of AST::Term).from(expr)
        ).from(expr),
      ] of AST::Term).from(orig),
      allow_non_partial_body: true,
    ).from(node)

    AST::Group.new("(", [try] of AST::Term).from(node)
  end

  def visit_assert_no_error(node : AST::Relate, expr : AST::Node)
    build_assert_has_error(node, expr, false)
  end

  def visit_assert_error(node : AST::Relate, expr : AST::Node)
    build_assert_has_error(node, expr, true)
  end

  def build_assert_has_error(node : AST::Relate, expr : AST::Node, expects_error : Bool)
    orig = node.lhs.as(AST::Group)

    try = AST::Try.new(
      AST::Group.new("(", [
        expr,
        AST::Identifier.new("False").from(expr),
      ] of AST::Term).from(expr),
      AST::Group.new("(", [
        AST::Identifier.new("True").from(expr)
      ] of AST::Term).from(expr)
    ).from(expr)

    expects_error = if expects_error
      AST::Identifier.new("True").from(node)
    else
      AST::Identifier.new("False").from(node)
    end

    call = AST::Call.new(
      AST::Identifier.new("Spec.Assert").from(orig),
      AST::Identifier.new("has_error").from(orig),
      AST::Group.new("(", [
        AST::Identifier.new("@").from(node),
        try,
        expects_error,
      ] of AST::Term).from(expr)
    ).from(orig)

    AST::Group.new("(", [call] of AST::Term).from(node)
  end

  def visit_source_code_position_of_argument(node : AST::Group)
    orig = node.terms[0]
    term = node.terms[1]

    Error.at term,
      "Expected this term to be an identifier" \
        unless term.is_a?(AST::Identifier)

    Error.at term,
      "Expected this term to be the identifier of a parameter, or `yield`",
        [{@func.params.not_nil!.pos,
          "it is supposed to refer to one of the parameters listed here"}] \
            unless AST::Extract.params(@func.params).map(&.first)
              .find { |param| param.value == term.value } \
                || term.value == "yield"

    Error.at node,
      "Expected this macro to be used as the default argument of a parameter",
        [{@func.params.not_nil!.pos,
          "it is supposed to be assigned to a parameter here"}] \
            unless AST::Extract.params(@func.params).map(&.last).includes?(node)

    op = AST::Operator.new("source_code_position_of_argument").from(orig)

    AST::Group.new("(", [
      AST::Prefix.new(op, term).from(node),
    ] of AST::Term).from(node)
  end

  def visit_stack_address_of_variable(node : AST::Group)
    orig = node.terms[0]
    term = node.terms[1]

    Error.at term,
      "Expected this term to be an identifier" \
        unless term.is_a?(AST::Identifier)

    op = AST::Operator.new("stack_address_of_variable").from(orig)

    AST::Group.new("(", [
      AST::Prefix.new(op, term).from(node),
    ] of AST::Term).from(node)
  end

  def visit_static_address_of_function(node : AST::Group)
    orig = node.terms[0]
    term = node.terms[1]

    Error.at term,
      "Expected this term to be a type name and function name " + \
      "with a dot in between" \
        unless term.is_a?(AST::Call)

    term_args = term.args || term.yield_params || term.yield_block
    Error.at term_args,
      "Expected this function to have no arguments" \
        if term_args

    op = AST::Operator.new("static_address_of_function").from(orig)

    AST::Group.new("(", [
      AST::Relate.new(term.receiver, op, term.ident).from(node),
    ] of AST::Term).from(node)
  end

  def visit_reflection_of_type(node : AST::Group)
    orig = node.terms[0]
    term = node.terms[1]

    op = AST::Operator.new("reflection_of_type").from(orig)

    AST::Group.new("(", [
      AST::Prefix.new(op, term).from(node),
    ] of AST::Term).from(node)
  end

  def visit_reflection_of_runtime_type_name(node : AST::Group)
    orig = node.terms[0]
    term = node.terms[1]

    op = AST::Operator.new("reflection_of_runtime_type_name").from(orig)

    AST::Group.new("(", [
      AST::Prefix.new(op, term).from(node),
    ] of AST::Term).from(node)
  end

  def visit_identity_digest_of(node : AST::Group)
    orig = node.terms[0]
    term = node.terms[1]

    op = AST::Operator.new("identity_digest_of").from(orig)

    AST::Group.new("(", [
      AST::Prefix.new(op, term).from(node),
    ] of AST::Term).from(node)
  end

  # Handle simple identifier macros like `error!` and `return` with no value.
  # We run these as a separate micro-pass so that we can ensure all other macros
  # have already been expanded before attempting to expand any of these.
  # Otherwise, these may interfere with expansion of multi-term forms
  # that use the same identifier as a marker (for example, `return VALUE`).
  class SimpleIdentifiers < Savi::AST::CopyOnMutateVisitor
    def self.run(ctx : Context, f : Program::Function, macros : Macros)
      visitor = new(macros)
      params = f.params.try(&.accept(ctx, visitor))
      body = f.body.try(&.accept(ctx, visitor))

      f = f.dup
      f.params = params
      f.body = body
      f
    end

    getter macros : Macros
    def initialize(@macros)
      @ignore_non_sequence_groups = [] of AST::Group
      @is_valid_sequential_context_stack = [] of Bool
    end

    def is_valid_sequential_context?
      @is_valid_sequential_context_stack[-2] == true
    end

    def pre_observe(ctx, node : AST::Node)
      case node
      when AST::Qualify
        @ignore_non_sequence_groups << node.group
      when AST::Call
        node.yield_params.try { |child| @ignore_non_sequence_groups << child }
      end

      case node
      when AST::Group
        if @ignore_non_sequence_groups.includes?(node)
          @ignore_non_sequence_groups.delete(node)
          @is_valid_sequential_context_stack << false
        elsif node.style != "(" && node.style != ":"
          @is_valid_sequential_context_stack << false
        else
          @is_valid_sequential_context_stack << true
        end
      when AST::Choice, AST::Loop, AST::Try
        @is_valid_sequential_context_stack << true
      else
        @is_valid_sequential_context_stack << false
      end
    end

    def post_observe(ctx, node : AST::Node)
      @is_valid_sequential_context_stack.pop
    end

    def visit_pre(ctx, node : AST::Node)
      pre_observe(ctx, node)
      node
    end

    def visit(ctx, node : AST::Node)
      node = maybe_replace(ctx, node)
      post_observe(ctx, node)
      node
    end

    def maybe_replace(ctx, node : AST::Node)
      return node unless node.is_a?(AST::Identifier)
      return node unless is_valid_sequential_context?

      case node.value
      when "error!"
        AST::Jump.new(AST::Identifier.new("None").from(node), AST::Jump::Kind::Error).from(node)
      when "return"
        AST::Jump.new(AST::Identifier.new("None").from(node), AST::Jump::Kind::Return).from(node)
      when "break"
        AST::Jump.new(AST::Identifier.new("None").from(node), AST::Jump::Kind::Break).from(node)
      when "next"
        AST::Jump.new(AST::Identifier.new("None").from(node), AST::Jump::Kind::Next).from(node)
      else
        node
      end
    end
  end
end
