require "./pass/analyze"

##
# The purpose of the Inventory pass is to take note of certain expressions.
#
# This pass does not mutate the Program topology.
# This pass does not mutate ASTs.
# This pass does not raise any compilation errors.
# This pass keeps temporary state at the per-function level.
# This pass produces output state at the per-function level.

struct Mare::Compiler::InventoryAnalysis
  def initialize
    @locals = [] of Refer::Local
    @yields = [] of AST::Yield
    @yielding_calls = [] of AST::Relate
  end

  def observe_local(x); @locals << x; end
  def observe_yield(x); @yields << x; end
  def observe_yielding_call(x); @yielding_calls << x; end

  def has_local?(x); @locals.includes?(x); end

  def yield_count; @yields.size; end
  def local_count; @locals.size; end

  def each_local; @locals.each end
  def each_yield; @yields.each end
  def each_yielding_call; @yielding_calls.each end
end

class Mare::Compiler::InventoryVisitor < Mare::AST::Visitor
  getter analysis : InventoryAnalysis
  getter refer : ReferAnalysis
  def initialize(@analysis, @refer)
  end

  def visit(ctx, node)
    case node
    when AST::Identifier
      if (ref = @refer[node]; ref)
        if ref.is_a?(Refer::Local)
          @analysis.observe_local(ref) unless @analysis.has_local?(ref)
        end
      end
    when AST::Yield
      @analysis.observe_yield(node)
    when AST::Relate
      if node.op.value == "."
        ident, args, yield_params, yield_block = AST::Extract.call(node)
        if yield_params || yield_block
          @analysis.observe_yielding_call(node)
        end
      end
    end

    node
  end
end

class Mare::Compiler::Inventory < Mare::Compiler::Pass::Analyze(
  Nil, # no analysis at the type level
  Mare::Compiler::InventoryAnalysis,
)
  def analyze_type(ctx, t, t_link)
    nil # no analysis at the type level
  end

  def analyze_func(ctx, f, f_link, t_analysis)
    refer = ctx.refer[f_link]
    visitor = InventoryVisitor.new(InventoryAnalysis.new, refer)

    f.params.try(&.accept(ctx, visitor))
    f.body.try(&.accept(ctx, visitor))

    visitor.analysis
  end
end
