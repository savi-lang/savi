require "./../../../../src/clim"

class MyCli < Clim
  main do
    desc "help directive test."
    usage "mycli [options] [arguments]"
    help short: "-h"
    run do |opts, args|
      # ...
    end
  end
end

MyCli.start(ARGV)
