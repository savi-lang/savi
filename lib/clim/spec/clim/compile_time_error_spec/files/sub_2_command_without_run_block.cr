require "./../../../../src/clim"

class MyCli < Clim
  main do
    run do |opts, args|
    end
    sub "sub" do
      run do |opts, args|
      end
      sub "sub_sub" do
        run do |opts, args|
        end
      end
    end
    sub "sub2" do
    end
  end
end

MyCli.start(ARGV)
