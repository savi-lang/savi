require "./../../../../src/clim"
require "big"

class MyCli < Clim
  main do
    option "", type: String, desc: "empty option name."
    run do |opts, args|
    end
  end
end

MyCli.start(ARGV)
