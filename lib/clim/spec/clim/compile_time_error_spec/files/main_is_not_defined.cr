require "./../../../../src/clim"

class MyCli < Clim
  sub do
    run do |opts, args|
    end
  end
end

MyCli.start(ARGV)
