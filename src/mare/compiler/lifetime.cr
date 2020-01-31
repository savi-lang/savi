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
    IsoMergeIntoCurrentRegion | IsoFreezeRegion)

  struct IsoMergeIntoCurrentRegion
    INSTANCE = new
  end

  struct IsoFreezeRegion
    INSTANCE = new
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

    def initialize(@ctx, @reach_def, @reach_func)
      @info_by_node = Hash(AST::Node, Info).new
    end

    def []?(node)
      @info_by_node[node]?
    end

    private def []=(node, info)
      @info_by_node[node] = info
    end

    # This visitor only touches nodes and does not mutate or replace them.
    def visit(node)
      touch(node)
      node
    end

    def touch(node : AST::Node)
      case node
      when AST::Relate
        case node.op.value
        when "="
          touch_move(node.rhs, node.lhs)
        # TODO: Handle more cases
        end
      # TODO: Handle more cases
      end
    end

    def touch_move(from_node : AST::Node, into_node : AST::Node)
      from_ref = @ctx.reach[@reach_func.infer.resolve(from_node)]
      into_ref = @ctx.reach[@reach_func.infer.resolve(into_node)]

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
        self[from_node] = IsoMergeIntoCurrentRegion::INSTANCE
      when {"iso+", "val"}
        # When an ephemeral iso is moved to an immutable cap,
        # it needs to be frozen, rendering its whole region immutable.
        self[from_node] = IsoFreezeRegion::INSTANCE
      else
        raise NotImplementedError.new("move #{from_cap} into #{into_cap}")
      end
    end
  end
end
