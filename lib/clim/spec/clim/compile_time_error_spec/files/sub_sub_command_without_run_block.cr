require "./../../../../src/clim"

class MyCli < Clim
  main do
    run do |opts, args|
    end
    sub "sub" do
      run do |opts, args|
      end
      sub "sub_sub" do
      end
    end
  end
end

MyCli.start(ARGV)
