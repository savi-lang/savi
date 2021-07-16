require "spec"
require "../src/savi"

module Spec::Methods
  def fixture(*parts)
    path = File.join(__DIR__, "fixtures", *parts)
    content = File.read(path)

    Savi::Source.new(
      File.dirname(path),
      File.basename(path),
      content,
      Savi::Source::Library.new(File.dirname(path)),
    )
  end
end
