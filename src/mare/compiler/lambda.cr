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
    @observed_refs_stack = [] of Hash(Int32, AST::Identifier)
  end
  
  def run
    @func.params.try &.accept(self)
    @func.body.try &.accept(self)
  end
  
  private def next_lambda_name
    "#{@type.ident.value}.#{@func.ident.value}.^#{@last_num += 1}"
  end
  
  def visit_pre(node : AST::Group)
    return node unless node.style == "^"
    
    @observed_refs_stack << Hash(Int32, AST::Identifier).new
    
    node
  end
  
  def visit(node : AST::Identifier)
    return node unless node.value.starts_with?("^")
    
    Error.at node, "A lambda parameter can't be used outside of a lambda" \
      if @observed_refs_stack.empty?
    
    # Strip the "^" from the start of the identifier
    node.value = node.value[1..-1]
    
    # Save the identifier in the observed refs for this lambda, mapped by num.
    # If we see the same identifier more than once, don't overwrite.
    num = node.value.to_i32
    @observed_refs_stack.last[num] ||= node
    
    node
  end
  
  def visit(node : AST::Group)
    return node unless node.style == "^"
    
    @changed = true
    name = next_lambda_name
    
    refs = @observed_refs_stack.pop
    unless refs.empty?
      param_count = refs.keys.max
      params = AST::Group.new("(").from(node)
      param_count.times.each do |i|
        params.terms << (refs[i + 1] || AST::Identifier.new("_").from(node))
      end
    end
    
    lambda_type = Program::Type.new(AST::Identifier.new(name).from(node))
    lambda_type.add_tag(:hygienic)
    @program.types << lambda_type
    
    lambda_type.functions << Program::Function.new(
      AST::Identifier.new("call").from(node),
      params,
      nil,
      node.dup.tap(&.style=(":")),
    )
    
    AST::Group.new("(").from(node).tap do |group|
      group.terms << AST::Identifier.new(name).from(node)
    end
  end
end
