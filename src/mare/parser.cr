require "./parser/lexer"
require "./parser/builder"

module Mare
  class Parser
    def initialize
      @lexer = Lexer.new
      @builder = Builder.new
    end
    
    def parse(source)
      ast = @lexer.parse(source)
      
      @builder.build(ast) if ast
    end
  end
end
