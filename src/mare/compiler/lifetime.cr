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
class Mare::Compiler::Lifetime
  alias Info = (
    IsoMergeIntoCurrentRegion | IsoFreezeRegion |
    PassAsArgument | ReleaseFromScope)

  struct IsoMergeIntoCurrentRegion
    INSTANCE = new
  end

  struct IsoFreezeRegion
    INSTANCE = new
  end

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
      reach_def.each_function(ctx).each do |reach_func|
        for_func = ForFunc.new(ctx, reach_def, reach_func)

        func = reach_func.infer.reified.func
        func.params.try(&.accept(for_func))
        func.body.try(&.accept(for_func))

        @info_by_func[reach_func] = for_func
      end
    end
  end

  class ForFunc < AST::Visitor
    @ctx : Compiler::Context
    @reach_def : Reach::Def
    @reach_func : Reach::Func

    def refer
      @ctx.refer[@reach_def.reified.defn][@reach_func.infer.reified.func]
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
    def visit_pre(node)
      touch_pre(node)
      node
    end
    def visit(node)
      touch(node)
      node
    end

    def touch_pre(node : AST::Node)
      case node
      when AST::Group
        scope = refer.scope?(node)
        touch_scope_pre(node, scope) if scope
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
          touch_move(node.rhs, node.lhs)
          touch_assign_local(node)
        when "."
          touch_call(node)
          # TODO: Handle more cases
        end
      # TODO: Handle more cases
      end
    end

    def touch_scope_pre(node, scope)
      @scopes << scope
    end

    def touch_scope_post(node, scope)
      popped_scope = @scopes.pop
      raise "scope stack inconsistency" unless popped_scope == scope

      popped_scope.locals.each do |local_name, local|
        # Take no action for variables that are also present in an outer scope.
        next if @scopes.any?(&.locals.has_key?(local_name))

        # Touch the local variable as it is falling out of scope and released.
        case local
        when Refer::Local
          touch_local_release(node, local)
        when Refer::LocalUnion
          local.list.each do |inner_local|
            touch_local_release(node, inner_local)
          end
        else
          raise NotImplementedError.new(local)
        end
      end
    end

    def touch_local_release(node : AST::Node, local : Refer::Local)
      insert(node, ReleaseFromScope.new(local))
    end

    def touch_assign_local(node : AST::Relate)
      node_lhs = node.lhs

      # We only deal in this function with assignments whose lhs is a Local.
      local = refer[node_lhs]
      return unless local.is_a?(Refer::Local)

      # When rebinding a var and not using the old value, we free/release it.
      if !Classify.value_needed?(node) && !local.is_defn_assign?(node)
        insert(node.lhs, ReleaseFromScope.new(local))
      end
    end

    def touch_call(node : AST::Relate)
      _, args, _, _ = AST::Extract.call(node)
      args.try(&.terms.each { |arg| touch_call_arg(arg) })
    end

    def touch_call_arg(node : AST::Node)
      # TODO: Sometimes may need IsoMergeIntoCurrentRegion or IsoFreezeRegion
      # or similar if passing an argument cap that doesn't match the param.

      insert(node, PassAsArgument::INSTANCE)
    end

    def touch_move(from_node : AST::Node, into_node : AST::Node)
      from_ref = @reach_func.resolve(@ctx, from_node)
      into_ref = @reach_func.resolve(@ctx, into_node)

      # If the type isn't changing, we have nothing to check on here.
      return if from_ref == into_ref

      # For now we only have supported this logic for singular types.
      raise NotImplementedError.new(from_ref.show_type) unless from_ref.singular?
      raise NotImplementedError.new(into_ref.show_type) unless into_ref.singular?
      from_def = from_ref.single_def!(@ctx)
      into_def = into_ref.single_def!(@ctx)

      # We don't handle lifetime of non-allocated types or cpointers.
      return if !from_def.has_allocation? || from_def.is_cpointer?

      # Based on the from and into cap, we determine an appropriate strategy
      # for handling the lifetime change (if any).
      from_cap = from_ref.cap_only.cap_value
      into_cap = into_ref.cap_only.cap_value
      case {from_cap, into_cap}
      when {"iso+", "ref"}, {"iso+", "box"}
        # When an ephemeral iso is moved to a local mutable cap,
        # it needs to be merged into the current local mutable region.
        insert(from_node, IsoMergeIntoCurrentRegion::INSTANCE)
      when {"iso+", "val"}
        # When an ephemeral iso is moved to an immutable cap,
        # it needs to be frozen, rendering its whole region immutable.
        insert(from_node, IsoFreezeRegion::INSTANCE)
      else
        raise NotImplementedError.new("move #{from_cap} into #{into_cap}")
      end
    end
  end
end
