require "pegmatite"

module Mare
  module Parser
    def self.parse(source)
      tokens = Pegmatite.tokenize(Grammar, source.content)
      
      Builder.build(tokens, source)
    end
  end
end
