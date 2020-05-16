##
# The purpose of the Verify pass is to do some various final checks before
# allowing the code to go through to CodeGen. For example, we verify here
# that function bodies that may raise an error belong to a partial function.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps temporay state at the per-function level.
# This pass produces no output state.
#
class Mare::Compiler::Verify < Mare::AST::Visitor
  def self.run(ctx, library)
    library.types.each do |t|
      t_link = t.make_link(library)
      ctx.infer[t_link].each_non_argumented_reified.each do |rt|
        t.functions.each do |f|
          f_link = f.make_link(t_link)
          jumps = ctx.jumps[f_link]
          inventory = ctx.inventory[f_link]

          ctx.infer[f_link].each_reified_func(rt).each do |rf|
            infer = ctx.infer[rf]

            visitor = new(infer, jumps, inventory)
            visitor.check_function(ctx, f)
            f.params.try(&.terms.each(&.accept(ctx, visitor)))
            f.body.try(&.accept(ctx, visitor))
          end
        end
      end
    end
  end

  getter infer : Infer::ReifiedFuncAnalysis
  getter jumps : Jumps::Analysis
  getter inventory : Inventory::Analysis

  def initialize(@infer, @jumps, @inventory)
  end

  def check_function(ctx, func)
    func_body = func.body

    if func_body && jumps.any_error?(func_body)
      if func.has_tag?(:constructor)
        finder = ErrorFinderVisitor.new(func_body, jumps)
        func_body.accept(ctx, finder)

        Error.at func.ident,
          "This constructor may raise an error, but that is not allowed",
          finder.found.map { |pos| {pos, "an error may be raised here"} }
      end

      if !jumps.any_error?(func.ident)
        finder = ErrorFinderVisitor.new(func_body, jumps)
        func_body.accept(ctx, finder)

        Error.at func.ident,
          "This function name needs an exclamation point "\
          "because it may raise an error", [
            {func.ident, "it should be named '#{func.ident.value}!' instead"}
          ] + finder.found.map { |pos| {pos, "an error may be raised here"} }
      end
    end

    # Require that async functions and constructors do not yield values.
    no_yields =
      if func.has_tag?(:async)
        "An asynchronous function"
      elsif func.has_tag?(:constructor)
        "A constructor"
      end
    if no_yields
      errs = [] of {Source::Pos, String}
      if func.yield_in || func.yield_out
        node = (func.yield_in || func.yield_out).not_nil!
        errs << {node.pos, "it declares a yield here"}
      end
      inventory.each_yield.each do |node|
        errs << {node.pos, "it yields here"}
      end
      Error.at func.ident, "#{no_yields} cannot yield values", errs \
        unless errs.empty?
    end
  end

  # This visitor never replaces nodes, it just touches them and returns them.
  def visit(ctx, node)
    touch(ctx, node)

    node
  end

  # Verify that each try block has at least one possible error case.
  def touch(ctx, node : AST::Try)
    unless node.body.try { |body| jumps.any_error?(body) }
      Error.at node, "This try block is unnecessary", [
        {node.body, "the body has no possible error cases to catch"}
      ]
    end
  end

  def touch(ctx, node : AST::Relate)
    case node.op.value
    when "<:"
      # Skip this verification if this just a compile-time type check.
      return if infer[node.lhs].is_a?(Infer::Fixed)

      # Verify that it is safe to perform this runtime type check.
      lhs_mt = infer.resolve(node.lhs)
      rhs_mt = infer.resolve(node.rhs)
      case lhs_mt.safe_to_match_as?(ctx, rhs_mt)
      when false
        Error.at node,
          "This type check would require runtime knowledge of capabilities", [
            {node.rhs.pos, "the target type is #{rhs_mt.show_type}"},
            {node.lhs.pos, "but the origin type #{lhs_mt.show_type} has " \
              "possibilities with the same type but different capability"}
          ]
      end
    end
  end

  def touch(ctx, node : AST::Node)
    # Do nothing for all other AST::Nodes.
  end

  # This visitor finds the most specific source positions that may raise errors.
  class ErrorFinderVisitor < Mare::AST::Visitor
    getter found
    getter jumps : Jumps::Analysis

    def initialize(node : AST::Node, @jumps)
      @found = [] of Source::Pos
      @deepest = node
    end

    # Only visit nodes that may raise an error.
    def visit_any?(ctx, node)
      @jumps.any_error?(node)
    end

    # Before visiting a node's children, mark this node as the deepest.
    # If any children can also raise errors, they will be the new deepest ones,
    # removing this node from the possibility of being considered deepest.
    def visit_pre(ctx, node)
      @deepest = node
    end

    # Save this source position if it is the deepest node in this branch of
    # the tree that we visited, recognizing that we skipped no-error branches.
    def visit(ctx, node)
      @found << node.pos if @deepest == node

      node
    end
  end
end
