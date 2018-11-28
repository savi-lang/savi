require "spec"
require "../src/mare"
require "./*"

module Spec::Methods
  def fixture(*parts)
    path = File.join(__DIR__, "fixtures", *parts)
    content = File.read(path)
    Mare::Source.new(path, content)
  end
end
