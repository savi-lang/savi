require "./../../../../src/clim"

class MyCli < Clim
  main do
    version "mycli version: 1.0.1", short: "-v"
    run do |opts, args|
      # ...
    end
  end
end

MyCli.start(ARGV)
