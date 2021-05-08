require "spec"
require "../src/mare"

module Spec::Methods
  def fixture(*parts)
    path = File.join(__DIR__, "fixtures", *parts)
    content = File.read(path)

    Mare::Source.new(
      File.dirname(path),
      File.basename(path),
      content,
      Mare::Source::Library.new(File.dirname(path)),
    )
  end
end
