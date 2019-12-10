class Mare::Compiler::Context
  getter program
  getter namespace
  getter refer_type
  getter inventory
  getter infer
  getter refer
  getter reach
  getter paint
  getter code_gen
  getter eval
  getter serve_hover
  
  def initialize
    @program = Program.new
    @stack = [Interpreter::Default.new(@program)] of Interpreter
    
    @namespace = Namespace.new
    @refer_type = ReferType.new
    @inventory = Inventory.new
    @infer = Infer.new
    @refer = Refer.new
    @reach = Reach.new
    @paint = Paint.new
    @code_gen = CodeGen.new
    @eval = Eval.new
    @serve_hover = ServeHover.new
  end
  
  def compile(doc : AST::Document)
    doc.list.each { |decl| compile(decl) }
    @stack.reverse_each &.finished(self)
  end
  
  def compile(decl : AST::Declare)
    loop do
      raise "Unrecognized keyword: #{decl.keyword}" if @stack.size == 0
      break if @stack.last.keywords.includes?(decl.keyword)
      @stack.pop.finished(self)
    end
    
    @stack.last.compile(self, decl)
  end
  
  def finish
    @stack.clear
  end
  
  def push(compiler)
    @stack.push(compiler)
  end
  
  def run(obj)
    obj.run(self)
    finish
    obj
  end
end
