require "./../../../../src/clim"

class MyCli < Clim
  main do
    run do |opts, args|
      # ...
    end
    sub "sub" do
      alias_name "alias1", "alias2"
      run do |opts, args|
        puts "sub_command run!!"
      end
    end
  end
end

MyCli.start(ARGV)
