require "./../../../../src/clim"

class MyCli < Clim
  main do
    help
    run do |opts, args|
    end
  end
end

MyCli.start(ARGV)
