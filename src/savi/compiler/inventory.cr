require "./pass/analyze"

##
# The purpose of the Inventory pass is to take note of certain expressions
# within functions, as well as taking note of the functions within types.
#
# This pass does not mutate the Program topology.
# This pass does not mutate ASTs.
# This pass does not raise any compilation errors.
# This pass keeps temporary state at the per-function level.
# This pass produces output state at the per-function level.
#
module Savi::Compiler::Inventory
  struct TypeAnalysis
    def initialize()
      @is_concrete = false
      @func_arities = Set({String, Int32}).new
      @is_assertions = [] of {Refer::Type, AST::Group?}
    end

    protected def observe_concreteness
      @is_concrete = true
    end

    protected def observe_func(f, f_link)
      @func_arities.add({f_link.name, f.params.try(&.terms.size) || 0})
    end

    protected def observe_is(f, f_link, refer_type)
      target_ast = f.ret.not_nil!

      @is_assertions << (
        case target_ast
        when AST::Identifier
          ident = target_ast
          {refer_type[ident].as(Refer::Type), nil}
        when AST::Qualify
          ident = target_ast.term.as(AST::Identifier)
          {refer_type[ident].as(Refer::Type), target_ast.group}
        else
          raise NotImplementedError.new(target_ast.to_a.inspect)
        end
      )
    end

    def is_concrete?; @is_concrete; end
    def func_count; @func_arities.size; end
    def each_func_arity; @func_arities.each; end
    def each_is_assertion; @is_assertions.each; end

    def has_func_arity?(x); @func_arities.includes?(x); end
  end

  struct Analysis
    def initialize
      @locals = [] of Refer::Local
      @yields = [] of AST::Yield
      @yielding_calls = [] of AST::Call
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

  class Visitor < Savi::AST::Visitor
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
      when AST::Call
        if node.yield_params || node.yield_block
          @analysis.observe_yielding_call(node)
        end
      else
      end

      node
    rescue exc : Exception
      raise Error.compiler_hole_at(node, exc)
    end
  end

  class Pass < Savi::Compiler::Pass::Analyze(Nil, TypeAnalysis, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil # no analysis at the type alias level
    end

    def analyze_type(ctx, t, t_link) : TypeAnalysis
      # TODO: is caching possible? is it necessary for such a simple pass?
      analysis = TypeAnalysis.new

      t.functions.each do |f|
        f_link = f.make_link(t_link)
        if f.has_tag?(:is)
          refer_type = ctx.refer_type[f_link]
          analysis.observe_is(f, f_link, refer_type)
        elsif f.has_tag?(:hygienic)
          # skip
        else
          analysis.observe_func(f, f_link)
        end
      end

      analysis
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
