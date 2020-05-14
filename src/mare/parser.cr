require "pegmatite"

module Mare::Parser
  def self.tokenize(source : Source)
    Pegmatite.tokenize(Grammar, source.content)
  end

  @@cache = {} of String => {Source, AST::Document}
  def self.parse(source : Source)
    if (cache_result = @@cache[source.path]?; cache_result)
      cached_source, cached_ast = cache_result
      return cached_ast if cached_source == source
    end

    Builder.build(tokenize(source), source)

    .tap do |result|
      @@cache[source.path] = {source, result}
    end
  end
end
