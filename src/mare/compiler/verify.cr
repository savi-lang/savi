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
class Mare::Compiler::Verify
  def self.check_main_actor(ctx, library)
    main_link = ctx.namespace.main_type?(ctx)
    main = main_link.try(&.resolve(ctx))

    unless main_link && main
      ctx.error_at Source::Pos.show_library_path(library.source_library),
        "This directory is being compiled, but it has no Main actor defined"
      return # we can't check anything further about Main when it doesn't exist
    end

    ctx.error_at main.ident,
      "The Main type defined here must be defined as an actor" \
        unless main.has_tag?(:actor)

    ctx.error_at main.params.not_nil!,
      "The Main actor is not allowed to have type parameters" \
        if main.params

    new_f = main.find_default_constructor?
    new_f_link = new_f.make_link(main_link.not_nil!) if new_f

    unless new_f_link && new_f
      ctx.error_at main.ident,
        "The Main actor defined here must have a constructor named `new`",
          main.functions.select(&.has_tag?(:constructor)) \
            .map { |f| {f.ident.pos, "this constructor is not named `new`"} }
      return # we can't check anything further about new when it doesn't exist
    end

    ctx.error_at new_f.not_nil!.ident,
      "The Main.new function defined here must be a constructor" \
        unless new_f.not_nil!.has_tag?(:constructor)

    env_link = ctx.namespace.prelude_type("Env")
    env = env_link.resolve(ctx)

    if new_f.param_count < 1
      ctx.error_at new_f.params || new_f.ident,
        "The Main.new function has too few parameters", [
          {env.ident.pos, "it should accept exactly one parameter of type Env"},
        ]
      return # we can't check anything further when no parameters are here
    elsif new_f.param_count > 1
      ctx.error_at new_f.params.not_nil!,
        "The Main.new function has too many parameters", [
          {env.ident.pos, "it should accept exactly one parameter of type Env"},
        ]
    end

    env_rt = Infer::ReifiedType.new(env_link)
    env_mt = Infer::MetaType.new(env_rt)
    main_rt = Infer::ReifiedType.new(main_link)
    main_mt_ref = Infer::MetaType.new(main_rt, "ref")
    new_rf = Infer::ReifiedFunction.new(main_rt, new_f_link, main_mt_ref)
    new_f_param = new_f.params.not_nil!.terms.first.not_nil!
    new_f_param_mt = new_rf.meta_type_of_param(ctx, 0, ctx.infer[new_f_link])

    ctx.error_at new_f_param,
      "The parameter of Main.new has the wrong type", [
        {env.ident.pos, "it should accept a parameter of type Env"},
        {ctx.pre_infer[new_f_link][new_f_param].pos,
          "but the parameter type is #{new_f_param_mt.try(&.show_type)}"},
      ] \
        unless new_f_param_mt == env_mt
  end

  class Visitor < Mare::AST::Visitor
    getter jumps : Jumps::Analysis
    getter inventory : Inventory::Analysis

    def initialize(@jumps, @inventory)
    end

    def check_function(ctx, func, func_link)
      func_body = func.body

      if func_body && jumps.any_error?(func_body)
        if func.has_tag?(:constructor) \
        && func_link.type.resolve(ctx).has_tag?(:actor)
          finder = ErrorFinderVisitor.new(func_body, jumps)
          func_body.accept(ctx, finder)

          ctx.error_at func.ident,
            "This actor constructor may raise an error, but that is not allowed",
            finder.found.map { |pos| {pos, "an error may be raised here"} }
        elsif !jumps.any_error?(func.ident)
          finder = ErrorFinderVisitor.new(func_body, jumps)
          func_body.accept(ctx, finder)

          ctx.error_at func.ident,
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
        ctx.error_at func.ident, "#{no_yields} cannot yield values", errs \
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
        ctx.error_at node, "This try block is unnecessary", [
          {node.body, "the body has no possible error cases to catch"}
        ]
      end
    end

    def touch(ctx, node : AST::Node)
      # Do nothing for all other AST::Nodes.
    end
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

  class Pass < Compiler::Pass::Analyze(Nil, Nil, Nil)
    def run(ctx, library)
      # If this is the "root" library, check that it has a Main actor,
      # and that the Main actor meets all requirements we expect.
      Verify.check_main_actor(ctx, library) \
        if library.make_link == ctx.namespace.root_library_link(ctx)

      super(ctx, library)
    end

    def analyze_type_alias(ctx, t, t_link) : Nil
      nil # no analysis output
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil # no analysis output
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Nil
      jumps = ctx.jumps[f_link]
      inventory = ctx.inventory[f_link]
      deps = {jumps, inventory}
      prev = ctx.prev_ctx.try(&.verify)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        visitor = Visitor.new(*deps)

        visitor.check_function(ctx, f, f_link)
        f.params.try(&.terms.each(&.accept(ctx, visitor)))
        f.body.try(&.accept(ctx, visitor))

        nil # no analysis output
      end
    end
  end
end
