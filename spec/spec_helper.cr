require "spec"
require "../src/mare"

module Spec::Methods
  def fixture(*parts)
    path = File.join(__DIR__, "fixtures", *parts)
    content = File.read(path)
    Mare::Source.new(path, content)
  end
end
