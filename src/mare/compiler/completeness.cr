##
# The purpose of the Completeness pass is to prove that constructors initialize
# all fields in the type that it constructs, such that no other code may ever
# interact with a readable reference to an uninitialized/NULL field.
# This validation work also includes typechecking of "self" references shared
# during a constructor before the type is "complete" (all fields initialized).
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps temporay state (on the stack) at the per-type level.
# This pass produces no output state.
#
module Mare::Compiler::Completeness
  def self.run(ctx, library)
    library.types.each do |t|
      t_link = t.make_link(library)
      ctx.infer[t_link].each_non_argumented_reified.each do |rt|
        branch_cache = {} of Tuple(Set(String), Infer::ReifiedFunction) => Branch
        t.functions.each do |f|
          f_link = f.make_link(t_link)
          ctx.infer[f_link].each_reified_func(rt).each do |rf|
            check_constructor(ctx, rt, rf, branch_cache)
          end
        end
      end
    end
  end

  def self.check_constructor(ctx, rt, rf, branch_cache)
    rf_func = rf.func(ctx)
    return unless rf_func.has_tag?(:constructor)

    fields = rt.defn(ctx).functions.select(&.has_tag?(:field))
    branch = Branch.new(ctx, rt, rf, branch_cache, fields)

    # First, visit the field initializers (for those fields that have them) as
    # sub branches to simulate them being run at the start of the constructor.
    fields.each do |next_f|
      next unless next_f.body
      branch.sub_branch(next_f.make_link(rt.link), "ref", next_f.ident.pos)
      branch.seen_fields.add(next_f.ident.value)
    end

    # Now visit the actual constructor body.
    rf_func.body.try(&.accept(ctx, branch))

    # Any fields that were not seen in the branching analysis are errors.
    unseen = branch.show_unseen_fields
    Error.at rf_func.ident,
      "This constructor doesn't initialize all of its fields", unseen \
        unless unseen.empty?
  end

  class Branch < Mare::AST::Visitor
    private getter ctx : Context
    getter type : Infer::ReifiedType
    getter func : Infer::ReifiedFunction
    getter branch_cache : Hash(Tuple(Set(String), Infer::ReifiedFunction), Branch)
    getter all_fields : Array(Program::Function)
    getter seen_fields : Set(String)
    getter call_crumbs : Array(Source::Pos)
    def initialize(
      @ctx,
      @type,
      @func,
      @branch_cache,
      @all_fields,
      @seen_fields = Set(String).new,
      @call_crumbs = Array(Source::Pos).new)
    end

    def sub_branch(node : AST::Node)
      branch =
        Branch.new(ctx, type, func, branch_cache, all_fields,
          seen_fields.dup, call_crumbs.dup)
      node.accept(ctx, branch)
      branch
    end

    def sub_branch(
      next_f_link : Program::Function::Link,
      next_f_cap : String,
      call_crumb : Source::Pos,
    )
      next_rf = ctx.infer[next_f_link]
        .each_reified_func(type)
        .find(&.receiver.cap_only.cap_value.==(next_f_cap)).not_nil!

      # Use caching of function branches to prevent infinite recursion.
      # We cache by both seen_fields and func so that we don't combine
      # cached results for branch paths where the set of prior seen fields
      # is different. This also lets us handle nicely some recursive patterns
      # that can be proven to make progress in the set of seen fields.
      cache_key = {seen_fields, next_rf}
      branch_cache.fetch cache_key do
        branch_cache[cache_key] = branch =
          Branch.new(ctx, type, next_rf, branch_cache, all_fields,
            seen_fields.dup, call_crumbs.dup)
        branch.call_crumbs << call_crumb
        next_rf.func(ctx).body.not_nil!.accept(ctx, branch)
        branch
      end
    end

    def show_unseen_fields
      all_fields
        .select(&.body.nil?) # ignore fields with a default initializer value
        .reject { |f| seen_fields.includes?(f.ident.value) }
        .map { |f| {f.ident, "this field didn't get initialized"} }
    end

    # This visitor never replaces nodes, it just touches them and returns them.
    def visit(ctx, node)
      touch(node)

      node
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

    def touch(node : AST::FieldWrite)
      seen_fields.add(node.value)
    end

    def touch(node : AST::FieldRead)
      if !seen_fields.includes?(node.value)
        Error.at node,
          "This field may be read before it is initialized by a constructor",
            call_crumbs.reverse.map { |pos| {pos, "traced from a call here"} }
      end
    end

    def touch(node : AST::Identifier)
      infer = ctx.infer[func]

      # Ignore this identifier if it is not of the self.
      info = infer[node]?
      return unless info.is_a?(Infer::Self)

      # We only care about further analysis if not all fields are initialized.
      return unless seen_fields.size < all_fields.size
      return if (unseen_fields = show_unseen_fields; unseen_fields).empty?

      # This represents the self type as opaque, with no field access.
      # We'll use this to guarantee that no usage of the current self object
      # will require  any access to the fields of the object.
      tag_self = Infer::MetaType.new(type, "tag")

      # Walk through each constraint imposed on the self in the earlier
      # Infer pass that tracked all of those constraints.
      info.domain_constraints.each do |pos, constraint|
        # If tag will meet the constraint, then this use of the self is okay.
        return if tag_self.subtype_of?(ctx, constraint)

        # Otherwise, we must raise an error.
        Error.at node,
          "This usage of `@` shares field access to the object" \
          " from a constructor before all fields are initialized", [
            {pos,
              "if this constraint were specified as `tag` or lower" \
              " it would not grant field access"}
          ] + unseen_fields
      end
    end

    def touch(node : AST::Relate)
      # We only care about looking at dot-relations (function calls).
      return unless node.op.value == "."

      # We only care about further analysis if not all fields are initialized.
      return unless seen_fields.size < all_fields.size

      # If the left side is definitely the self, we allow access even when
      # not all fields are initialized - we will follow the call and continue
      # our branching analysis of field initialization in that other function.
      lhs = node.lhs
      if lhs.is_a?(AST::Identifier) && lhs.value == "@"
        # Extract the function name from the right side.
        func_name = AST::Extract.call(node)[0].value

        # Follow the method call in a new branch, and collect any field writes
        # seen in that branch as if they had been seen in this branch.
        next_f = type.defn(ctx).find_func!(func_name)
        next_f_cap = next_f.cap.value # TODO: reify with which cap?
        branch = sub_branch(next_f.make_link(type.link), next_f_cap, node.pos)
        seen_fields.concat(branch.seen_fields)
      end
    end

    def touch(node : AST::Node)
      # Do nothing for all other AST::Nodes.
    end
  end
end
