class Mare::Compiler::Lambda < Mare::AST::Visitor
  def self.run(ctx)
    ctx.program.types.each do |t|
      t.functions.each do |f|
        new(ctx.program, t, f).run
      end
    end
  end
  
  @program : Program
  @type : Program::Type
  @func : Program::Function
  def initialize(@program, @type, @func)
    @last_num = 0
    @changed = false
  end
  
  def run
    @func.params.try &.accept(self)
    @func.body.try &.accept(self)
    @func.invalidate_refer! if @changed
  end
  
  private def next_lambda_name
    "#{@type.ident.value}.#{@func.ident.value}.^#{@last_num += 1}"
  end
  
  def visit(node : AST::Group)
    return node unless node.style == "^"
    
    @changed = true
    name = next_lambda_name
    
    lambda_type = Program::Type.new(AST::Identifier.new(name).from(node))
    lambda_type.add_tag(:hygienic)
    @program.types << lambda_type
    
    lambda_type.functions << Program::Function.new(
      AST::Identifier.new("call").from(node),
      nil,
      nil,
      node.dup.tap(&.style=(":")),
    )
    
    AST::Group.new("(").from(node).tap do |group|
      group.terms << AST::Identifier.new(name).from(node)
    end
  end
end
