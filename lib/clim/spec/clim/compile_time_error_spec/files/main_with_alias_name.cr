require "./../../../../src/clim"

class MyCli < Clim
  main do
    alias_name "main2"
    run do |opts, args|
    end
  end
end

MyCli.start(ARGV)
