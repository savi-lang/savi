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
  @@cache = {} of String => {UInt64, Program::Function}
  def self.cache_key(l, t, f)
    t.ident.value + "\0" + f.ident.value
  end
  def self.cached_or_run(l, t, f) : Program::Function
    input_hash = f.hash
    # input_hash = f.structural_hash
    cache_key = cache_key(l, t, f)
    cache_result = @@cache[cache_key]?
    cached_hash, cached_func = cache_result if cache_result
    return cached_func if cached_func && cached_hash == input_hash

    yield

    .tap do |result|
      @@cache[cache_key] = {input_hash, result}
    end
  end

  def self.run(ctx, library)
    library.types_map_cow do |t|
      t.functions_map_cow do |f|
        cached_or_run library, t, f do
          macros = new(f)
          macros.maybe_compiler_intrinsic
          macros.run(ctx)
        end
      end
    end
  end

  getter func
  def initialize(@func : Program::Function)
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
      Util.require_terms(node, [
        nil,
        "the value to be yielded out to the calling function",
      ])
      visit_yield(node)
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
    elsif Util.match_ident?(node, 0, "identity_digest_of")
      Util.require_terms(node, [
        nil,
        "the value whose identity is to be hashed",
      ])
      visit_identity_digest_of(node)
    elsif Util.match_ident?(node, 1, "is")
      Util.require_terms(node, [
        "one of the two operands whose identity is to be compared",
        nil,
        "the other of the two operands whose identity is to be compared",
      ])
      visit_is(node)
    elsif Util.match_ident?(node, 1, "isnt")
      Util.require_terms(node, [
        "one of the two operands whose identity is to be compared",
        nil,
        "the other of the two operands whose identity is to be compared",
      ])
      visit_isnt(node)
    else
      node
    end
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
    cond = node.terms[1]
    body = node.terms[2]
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
      AST::Loop.new(cond, body, else_body).from(orig),
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

  def visit_identity_digest_of(node : AST::Group)
    orig = node.terms[0]
    term = node.terms[1]

    op = AST::Operator.new("identity_digest_of").from(orig)

    AST::Group.new("(", [
      AST::Prefix.new(op, term).from(node),
    ] of AST::Term).from(node)
  end

  def visit_is(node : AST::Group)
    lhs = node.terms[0]
    orig = node.terms[1]
    rhs = node.terms[2]

    op = AST::Operator.new("is").from(orig)

    AST::Group.new("(", [
      AST::Relate.new(lhs, op, rhs).from(node),
    ] of AST::Term).from(node)
  end

  def visit_isnt(node : AST::Group)
    lhs = node.terms[0]
    orig = node.terms[1]
    rhs = node.terms[2]

    op = AST::Operator.new("is").from(orig)

    AST::Group.new("(", [
      AST::Relate.new(
        AST::Relate.new(lhs, op, rhs).from(node),
        AST::Operator.new(".").from(node),
        AST::Identifier.new("not").from(node),
      ).from(node)
    ] of AST::Term).from(node)
  end
end
