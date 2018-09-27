require "spec"
require "../src/mare"

module Spec::Methods
  def fixture(*parts)
    File.read(File.join(__DIR__, "fixtures", *parts))
  end
end
