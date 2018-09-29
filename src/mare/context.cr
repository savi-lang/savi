module Mare
  class Context
    def initialize(
      @stack = [Compiler::Default.new] of Compiler,
      @reactor = Reactor.new)
    end
    
    def compile(doc : AST::Document)
      doc.list.each { |decl| compile(decl) }
    end
    
    def compile(decl : AST::Declare)
      @stack.last.compile(self, decl)
    end
    
    def push(compiler)
      @stack.push(compiler)
    end
    
    def on(x_class : X.class, path, &block : X -> Nil): Nil forall X
      @reactor.on(x_class, path, &block)
    end
    
    def fulfill(path, x : X): Nil forall X
      @reactor.fulfill(path, x)
    end
  end
end