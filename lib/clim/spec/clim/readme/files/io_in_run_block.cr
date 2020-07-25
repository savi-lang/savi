require "./../../../../src/clim"

class IoCommand < Clim
  main do
    run do |opts, args, io|
      io.puts "in main"
    end
  end
end

io = IO::Memory.new
IoCommand.start([] of String, io: io)
puts io.to_s # => "in main\n"
