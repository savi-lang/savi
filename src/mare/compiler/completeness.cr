##
# The purpose of the Completeness pass is to prove that constructors initialize
# all fields in the type that it constructs, such that no other code may ever
# interact with a readable reference to an uninitialized/NULL field.
#
# This validation work also includes storing analysis of "self" references
# shared during a constructor before the type is "complete"
# (all fields initialized) so that the later TypeCheck pass can confirm that
# the tag capability is all that is needed to satisfy those.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the per-function level for constructors.
# This pass produces output state at the per-function level for constructors.
#
module Mare::Compiler::Completeness
  struct Analysis
    def initialize
      @unseen_fields_for_each_self_reference =
        {} of Infer::Self => Array(AST::Identifier)
    end

    protected def observe_self_reference(
      info : Infer::Self,
      unseen_fields : Array(AST::Identifier)
    )
      @unseen_fields_for_each_self_reference[info] = unseen_fields
    end

    def unseen_fields_for(info : Infer::Self)
      list = @unseen_fields_for_each_self_reference[info]?
      return nil unless list
      return nil if list.empty?
      list
    end
  end

  def self.check_constructor(ctx, f, f_link, analysis)
    t = f_link.type.resolve(ctx)
    return analysis unless f.has_tag?(:constructor)

    branch_cache = {} of Tuple(Set(String), Program::Function::Link) => Branch
    fields = t.functions.select(&.has_tag?(:field))
    let_fields = fields.select(&.has_tag?(:let)).map(&.ident.value).to_set
    branch = Branch.new(ctx, t, f, f_link, analysis, branch_cache, fields, let_fields)

    # First, visit the field initializers (for those fields that have them) as
    # sub branches to simulate them being run at the start of the constructor.
    fields.each do |next_f|
      next unless next_f.body
      branch.sub_branch(ctx, next_f, next_f.make_link(f_link.type), next_f.ident.pos)
      branch.seen_fields.add(next_f.ident.value)
    end

    # Now visit the actual constructor body.
    f.body.try(&.accept(ctx, branch))

    # Any fields that were not seen in the branching analysis are errors.
    unseen = branch.show_unseen_fields
    ctx.error_at f.ident,
      "This constructor doesn't initialize all of its fields", unseen \
        unless unseen.empty?

    branch.analysis
  end

  class Branch < Mare::AST::Visitor
    private getter ctx : Context
    getter type : Program::Type
    getter func : Program::Function
    getter func_link : Program::Function::Link
    getter analysis : Analysis
    getter branch_cache : Hash(Tuple(Set(String), Program::Function::Link), Branch)
    getter all_fields : Array(Program::Function)
    getter let_fields : Set(String)
    getter seen_fields : Set(String)
    getter call_crumbs : Array(Source::Pos)
    getter jumps : Jumps::Analysis
    getter pre_infer : PreInfer::Analysis

    def initialize(
      @ctx,
      @type,
      @func,
      @func_link,
      @analysis,
      @branch_cache,
      @all_fields,
      @let_fields,
      @seen_fields = Set(String).new,
      @call_crumbs = Array(Source::Pos).new,
      @possibly_away = false,
      @loop_stack = [] of AST::Loop,
    )
      @jumps = @ctx.jumps[@func_link]
      @pre_infer = @ctx.pre_infer[@func_link]
    end

    def sub_branch(node : AST::Node)
      branch =
        Branch.new(ctx, type, func, func_link, analysis, branch_cache,
          all_fields, let_fields, seen_fields.dup, call_crumbs.dup)
      node.accept(ctx, branch)
      branch
    end

    def sub_branch(
      ctx : Context,
      next_f : Program::Function,
      next_f_link : Program::Function::Link,
      call_crumb : Source::Pos,
      possibly_away = false,
    )
      # Use caching of function branches to prevent infinite recursion.
      # We cache by both seen_fields and func so that we don't combine
      # cached results for branch paths where the set of prior seen fields
      # is different. This also lets us handle nicely some recursive patterns
      # that can be proven to make progress in the set of seen fields.
      cache_key = {seen_fields, next_f_link}
      branch_cache.fetch cache_key do
        branch_cache[cache_key] = branch =
          Branch.new(ctx, type, next_f, next_f_link, analysis, branch_cache,
            all_fields, let_fields, seen_fields.dup, call_crumbs.dup,
            possibly_away, @loop_stack)
        branch.call_crumbs << call_crumb
        next_f.body.not_nil!.accept(ctx, branch)
        branch
      end
    end

    def collect_unseen_fields
      all_fields
        .select(&.body.nil?) # ignore fields with a default initializer value
        .reject { |f| seen_fields.includes?(f.ident.value) }
        .map(&.ident)
    end

    def show_unseen_fields
      collect_unseen_fields
        .map { |ident| {ident, "this field didn't get initialized"} }
    end

    def visit_pre(ctx, node)
      if node.is_a? AST::Loop
        @loop_stack << node
      end
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end

    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(ctx, node)
      touch(node)

      if node.is_a? AST::Loop
        @loop_stack.pop
      end

      node
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end

    def visit_children?(ctx, node : AST::Choice)
      # We don't visit anything under a choice with this visitor;
      # we instead spawn a new visitor instance in the touch method below.
      false
    end

    def touch(node : AST::Choice)
      # Visit the body of each clause with a new instance of this visitor,
      # and collect the fields that appeared in all child branches.
      # A field counts as initialized if it is initialized in all branches.
      seen_fields.concat(
        node.list
          .map { |cond, body| sub_branch(body).seen_fields }
          .reduce { |accum, fields| accum & fields }
      )
    end

    def touch(node : AST::FieldRead)
      if !seen_fields.includes?(node.value)
        ctx.error_at node,
          "This field may be read before it is initialized by a constructor",
            call_crumbs.reverse.map { |pos| {pos, "traced from a call here"} }
      end
    end

    def touch(node : AST::FieldWrite)
      seen_fields.add(node.value) unless @possibly_away ||\
        !@loop_stack.empty? || @jumps.away_possibly?(node)
    end

    def touch(node : AST::FieldReplace)
      if !seen_fields.includes?(node.value)
        ctx.error_at node,
          "This field may be read (via displacing assignment) " +
          "before it is initialized by a constructor",
            call_crumbs.reverse.map { |pos| {pos, "traced from a call here"} }
      end
      seen_fields.add(node.value) unless @possibly_away ||\
        !@loop_stack.empty? || @jumps.away_possibly?(node)
    end

    def touch(node : AST::Identifier)
      # Ignore this identifier if it is not of the self.
      info = @pre_infer[node]?
      return unless info.is_a?(Infer::Self)

      @analysis.observe_self_reference(info, collect_unseen_fields)
    end

    def touch(node : AST::Relate)
      # We only care about looking at dot-relations (function calls).
      return unless node.op.value == "."

      # If the left side is definitely the self, we allow access even when
      # not all fields are initialized - we will follow the call and continue
      # our branching analysis of field initialization in that other function.
      lhs = node.lhs
      if lhs.is_a?(AST::Identifier) && lhs.value == "@"
        # Extract the function name from the right side.
        func_name = AST::Extract.call(node)[0].value

        # If this is a direct call to a `let` property setter, complain
        # if this object has already been fully initialized in all fields.
        # All indirect calls to this setter/displacer will error elsewhere,
        # where we prove that it is never called outside a constructor.
        if call_crumbs.empty? && (
          (
            func_name.ends_with?("=") &&
            let_fields.includes?(let_name = func_name[0...-1])
          ) || (
            func_name.ends_with?("<<=") &&
            let_fields.includes?(let_name = func_name[0...-3])
          )
        ) && collect_unseen_fields.empty?
          ctx.error_at node, "A `let` property cannot be reassigned " +
            "after all fields have been initialized", [{
              all_fields.find(&.ident.value.==(let_name)).not_nil!.ident.pos,
              "declare this property with `var` instead of `let` if reassignment is needed"
            }]
        end

        # We only care about further analysis if not all fields are initialized.
        return unless seen_fields.size < all_fields.size

        # Follow the method call in a new branch, and collect any field writes
        # seen in that branch as if they had been seen in this branch.
        next_f = type.find_func!(func_name)
        branch = sub_branch(ctx, next_f, next_f.make_link(func_link.type), node.pos, @jumps.away_possibly?(node))
        seen_fields.concat(branch.seen_fields)
      end
    end

    def touch(node : AST::Node)
      # Do nothing for all other AST::Nodes.
    end
  end

  class Pass < Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil # no analysis output
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil # no analysis output
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      # TODO: Try to enable caching once we have a way to invalidate the cache
      # when any of the other functions we call in the constructor have changed.
      Completeness.check_constructor(ctx, f, f_link, Analysis.new)
    end
  end
end
