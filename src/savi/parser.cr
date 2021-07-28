require "pegmatite"

module Savi::Parser
  @@cache = {} of String => {Source, AST::Document}
  def self.parse(source : Source)
    if (cache_result = @@cache[source.path]?; cache_result)
      cached_source, cached_ast = cache_result
      return cached_ast if cached_source == source
    end

    grammar =
      case source.language
      when :savi then Grammar
      else raise NotImplementedError.new("#{source.language} language parsing")
      end

    Builder.build(Pegmatite.tokenize(grammar, source.content), source)

    .tap do |result|
      @@cache[source.path] = {source, result}
    end
  end
end
