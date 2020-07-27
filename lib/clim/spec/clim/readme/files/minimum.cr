require "./../../../../src/clim"

class MyCli < Clim
  main do
    run do |opts, args|
      puts "#{args.all_args.join(", ")}!"
    end
  end
end

MyCli.start(ARGV)
