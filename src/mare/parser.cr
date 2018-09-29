module Mare
  class Parser
    def initialize
      @lexer = Lexer.new
      @builder = Builder.new
    end
    
    def parse(source)
      ast = @lexer.parse(source.content)
      
      @builder.build(source, ast) if ast
    end
  end
end
