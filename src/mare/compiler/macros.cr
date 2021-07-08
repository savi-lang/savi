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
class Mare::Compiler::Macros < Mare::AST::CopyOnMutateVisitor
  # TODO: This class should interpret macro declarations by the user and treat
  # those the same as macro declarations in the prelude, with both getting
  # executed here dynamically instead of declared here statically.

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

  def visit(ctx, node : AST::Group)
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
    elsif Util.match_ident?(node, 0, "address_of")
      Util.require_terms(node, [
        nil,
        "the local variable whose address is to be referenced",
      ])
      visit_address_of(node)
    else
      node
    end
  rescue exc : Exception
    raise exc if exc.is_a?(Error) # TODO: ctx.errors multi-error capability
    raise Error.compiler_hole_at(node, exc)
  end

  def visit(ctx, node : AST::Call)
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

  # This clause picks up a special form of case which is inside a Relate node,
  # where the Relate gets reshuffled into the case clauses.
  # We need it to be a visit_pre rather than a normal visit, because
  # if we visited the children first as we normally do, then it would try
  # to expand the `case` macro inside the Relate before running this code,
  # and fail because the inner `case` Group doesn't have the right terms.
  def visit_pre(ctx, node : AST::Relate)
    lhs = node.lhs
    return node unless \
      lhs.is_a?(AST::Group) &&
      lhs.style == " " &&
      Util.match_ident?(lhs, 0, "case")

    term = lhs.terms[1]
    Error.at term,
      "Expected this term to be not be a parenthesized group" \
        if term.is_a?(AST::Group) && (term.style == "(" || term.style == "|")

    group = node.rhs
    Error.at group,
      "Expected this term to be a parenthesized group of cases to check,\n" \
      "  partitioned into sections by `|`, in which each body section\n" \
      "  is preceded by a condition section to be evaluated as a Bool,\n" \
      "  with an optional else body section at the end" \
        unless group.is_a?(AST::Group) && group.style == "|"

    visit_case(node)
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

  def visit_source_code_position_of_argument(node : AST::Group)
    orig = node.terms[0]
    term = node.terms[1]

    Error.at term,
      "Expected this term to be an identifier" \
        unless term.is_a?(AST::Identifier)

    Error.at term,
      "Expected this term to be the identifier of a parameter",
        [{@func.params.not_nil!.pos,
          "it is supposed to refer to one of the parameters listed here"}] \
            unless AST::Extract.params(@func.params).map(&.first)
              .find { |param| param.value == term.value }

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

  def visit_address_of(node : AST::Group)
    orig = node.terms[0]
    term = node.terms[1]

    op = AST::Operator.new("address_of").from(orig)

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
  class SimpleIdentifiers < Mare::AST::CopyOnMutateVisitor
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
        node.args.try { |child| @ignore_non_sequence_groups << child }
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
