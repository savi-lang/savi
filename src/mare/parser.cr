require "pegmatite"

module Mare::Parser
  # TODO: Cache AST::Document instead of Array(Pegmatite::Token) as soon as
  # copy-on-mutate patterns are enforced throughout the codebase.
  @@cache = {} of String => {Source, Array(Pegmatite::Token)}

  def self.tokenize(source : Source)
    if (cache_result = @@cache[source.path]?; cache_result)
      cached_source, cached_tokens = cache_result
      return cached_tokens if cached_source == source
    end

    Pegmatite.tokenize(Grammar, source.content)

    .tap do |result|
      @@cache[source.path] = {source, result}
    end
  end

  def self.parse(source : Source)
    Builder.build(tokenize(source), source)
  end
end
