##
# The purpose of the Lifetime pass is to analyze forms to determine locations
# where values fall out of scope or change reference capability in ways that
# are relevant to the reference counting and book-keeping in the Verona runtime.
# Ultimately this pass is responsible in large part for the memory safety and
# correctness of our usage of the Verona runtime, so special care should be
# exercised in ensuring that the analysis here is complete and correct.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the function level.
# This pass produces output state at the per-function level.
#
class Savi::Compiler::Lifetime
  alias Info = (PassAsArgument | ReleaseFromScope)

  struct PassAsArgument
    INSTANCE = new
  end

  struct ReleaseFromScope
    getter local : Refer::Local

    def initialize(@local)
    end
  end

  def initialize
    @info_by_func = Hash(Reach::Func, ForFunc).new
  end

  def [](reach_func)
    @info_by_func[reach_func]
  end

  def run(ctx)
    ctx.reach.each_type_def.each do |reach_def|
      ctx.reach.reached_funcs_for(reach_def).each do |reach_func|
        for_func = ForFunc.new(ctx, reach_def, reach_func)

        func = reach_func.reified.func(ctx)
        func.params.try(&.accept(ctx, for_func))
        func.body.try(&.accept(ctx, for_func))

        @info_by_func[reach_func] = for_func
      end
    end
  end

  class ForFunc < AST::Visitor
    @ctx : Compiler::Context
    @reach_def : Reach::Def
    @reach_func : Reach::Func

    def refer
      @ctx.refer[@reach_func.reified.link]
    end

    def classify
      @ctx.classify[@reach_func.reified.link]
    end

    def local
      @ctx.local[@reach_func.reified.link]
    end

    def initialize(@ctx, @reach_def, @reach_func)
      @infos_by_node = Hash(AST::Node, Array(Info)).new
      @scopes = [] of Refer::Scope
    end

    def []?(node)
      @infos_by_node[node]?
    end

    private def insert(node, info)
      (@infos_by_node[node] ||= ([] of Info)).not_nil! << info
    end

    # This visitor only touches nodes and does not mutate or replace them.
    def visit_pre(ctx, node)
      touch_pre(node)
      node
    end
    def visit(ctx, node)
      touch(node)
      node
    end

    def touch_pre(node : AST::Node)
      case node
      when AST::Group
        scope = refer.scope?(node)
        touch_scope_pre(node, scope) if scope
      else
        nil
      end
    end
    def touch(node : AST::Node)
      case node
      when AST::Group
        scope = refer.scope?(node)
        touch_scope_post(node, scope) if scope
      when AST::Relate
        case node.op.value
        when "="
          touch_assign_local(node)
          # TODO: Handle more cases
        else
          nil
        end
      # TODO: Handle more cases
      when AST::Call
        touch_call(node)
      else
        nil
      end
    end

    def touch_scope_pre(node, scope)
      @scopes << scope
    end

    def touch_scope_post(node, scope)
      popped_scope = @scopes.pop
      raise "scope stack inconsistency" unless popped_scope == scope

      popped_scope.locals.each do |local_name, ref|
        # Take no action for variables that are also present in an outer scope.
        next if @scopes.any?(&.locals.has_key?(local_name))

        # Touch the local variable as it is falling out of scope and released.
        case ref
        when Refer::Local
          touch_local_release(node, ref)
        else
          raise NotImplementedError.new(ref)
        end
      end
    end

    def touch_local_release(node : AST::Node, ref : Refer::Local)
      insert(node, ReleaseFromScope.new(ref))
    end

    def touch_assign_local(node : AST::Relate)
      node_lhs = node.lhs

      # We only deal in this function with assignments whose lhs is a Local.
      ref = refer[node_lhs]
      return unless ref.is_a?(Refer::Local)

      # When rebinding a var and not using the old value, we free/release it.
      if !classify.value_needed?(node) && !local[node].is_initial_site
        insert(node.lhs, ReleaseFromScope.new(ref))
      end
    end

    def touch_call(node : AST::Call)
      node.args.try(&.terms.each { |arg| touch_call_arg(arg) })
    end

    def touch_call_arg(node : AST::Node)
      insert(node, PassAsArgument::INSTANCE)
    end
  end
end
