##
# The purpose of the Egress pass is to take note of yield expressions.
#
# This pass does not mutate the Program topology.
# This pass does not mutate ASTs.
# This pass does not raise any compilation errors.
# This pass keeps temporary state (on the stack) at the per-function level.
# This pass produces output state at the per-function level.
#
class Mare::Compiler::Egress < Mare::AST::Visitor
  getter yields
  
  @current_func : Program::Function?
  def initialize
    @current_func = nil
    @yields = {} of Program::Function => Array(AST::Yield)
  end
  
  def run(ctx)
    ctx.program.types.each do |t|
      t.functions.each do |f|
        @current_func = f
        f.body.try(&.accept(self))
      end
    end
    @current_func = nil
  end
  
  def visit(node)
    if node.is_a?(AST::Yield)
      (@yields[@current_func.not_nil!] ||= ([] of AST::Yield)) << node
    end
    
    node
  end
end
