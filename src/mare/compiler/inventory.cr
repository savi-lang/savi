##
# The purpose of the Inventory pass is to take note of certain expressions.
#
# This pass does not mutate the Program topology.
# This pass does not mutate ASTs.
# This pass does not raise any compilation errors.
# This pass keeps temporary state at the per-function level.
# This pass produces output state at the per-function level.
#
class Mare::Compiler::Inventory < Mare::AST::Visitor
  getter! current_ctx : Context?
  getter! current_type : Program::Type?
  getter! current_func : Program::Function?

  def initialize
    @locals = {} of Program::Function => Array(Refer::Local)
    @yields = {} of Program::Function => Array(AST::Yield)
    @yielding_calls = {} of Program::Function => Array(AST::Relate)
  end

  def locals(func)
    @locals[func]? || [] of Refer::Local
  end

  def yields(func)
    @yields[func]? || [] of AST::Yield
  end

  def yielding_calls(func)
    @yielding_calls[func]? || [] of AST::Relate
  end

  def run(ctx, library)
    @current_ctx = ctx
    library.types.each do |t|
      @current_type = t
      t.functions.each do |f|
        @current_func = f
        f.params.try(&.accept(self))
        f.body.try(&.accept(self))
      end
    end
    @current_ctx = nil
    @current_type = nil
    @current_func = nil
  end

  def visit(node)
    case node
    when AST::Identifier
      if (ref = current_ctx.refer[current_type][current_func][node]; ref)
        if ref.is_a?(Refer::Local)
          list = (@locals[current_func] ||= ([] of Refer::Local))
          list << ref unless list.includes?(ref)
        end
      end
    when AST::Yield
      (@yields[current_func] ||= ([] of AST::Yield)) << node
    when AST::Relate
      if node.op.value == "."
        ident, args, yield_params, yield_block = AST::Extract.call(node)
        if yield_params || yield_block
          (@yielding_calls[current_func] ||= ([] of AST::Relate)) << node
        end
      end
    end

    node
  end
end
