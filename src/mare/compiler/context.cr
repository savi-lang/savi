class Mare::Compiler::Context
  getter program
  getter infers
  getter refers
  
  def initialize
    @program = Program.new
    @stack = [Interpreter::Default.new(@program)] of Interpreter
    @infers = Infers.new
    @refers = Refers.new
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
