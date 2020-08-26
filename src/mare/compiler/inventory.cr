require "./pass/analyze"

##
# The purpose of the Inventory pass is to take note of certain expressions.
#
# This pass does not mutate the Program topology.
# This pass does not mutate ASTs.
# This pass does not raise any compilation errors.
# This pass keeps temporary state at the per-function level.
# This pass produces output state at the per-function level.
#
module Mare::Compiler::Inventory
  struct Analysis
    def initialize
      @locals = [] of Refer::Local
      @yields = [] of AST::Yield
      @yielding_calls = [] of AST::Relate
    end

    protected def observe_local(x); @locals << x; end
    protected def observe_yield(x); @yields << x; end
    protected def observe_yielding_call(x); @yielding_calls << x; end

    def has_local?(x); @locals.includes?(x); end

    def local_count; @locals.size; end
    def yield_count; @yields.size; end
    def yielding_call_count; @yielding_calls.size; end

    def each_local; @locals.each end
    def each_yield; @yields.each end
    def each_yielding_call; @yielding_calls.each end
  end

  class Visitor < Mare::AST::Visitor
    getter analysis : Analysis
    getter refer : Refer::Analysis
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
      else
      end

      node
    end
  end

  class Pass < Mare::Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil # no analysis at the type level
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil # no analysis at the type level
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      refer = ctx.refer[f_link]
      deps = refer
      prev = ctx.prev_ctx.try(&.inventory)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        visitor = Visitor.new(Analysis.new, refer)

        f.params.try(&.accept(ctx, visitor))
        f.body.try(&.accept(ctx, visitor))

        visitor.analysis
      end
    end
  end
end
