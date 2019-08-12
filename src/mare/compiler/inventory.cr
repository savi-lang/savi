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
  getter yields
  getter locals
  getter! current_ctx : Context?
  getter! current_type : Program::Type?
  getter! current_func : Program::Function?
  
  def initialize
    @yields = {} of Program::Function => Array(AST::Yield)
    @locals = {} of Program::Function => Array(Refer::Local)
  end
  
  def run(ctx)
    @current_ctx = ctx
    ctx.program.types.each do |t|
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
    when AST::Yield
      (yields[current_func] ||= ([] of AST::Yield)) << node
    when AST::Identifier
      if (ref = current_ctx.refer[current_type][current_func][node]; ref)
        if ref.is_a?(Refer::Local)
          list = (locals[current_func] ||= ([] of Refer::Local))
          list << ref unless list.includes?(ref)
        end
      end
    end
    
    node
  end
end
