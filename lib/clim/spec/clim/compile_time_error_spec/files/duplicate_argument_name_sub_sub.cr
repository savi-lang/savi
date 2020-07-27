require "./../../../../src/clim"

class MyCli < Clim
  main do
    argument "foo"
    argument "bar"
    run do |opts, args|
    end
    sub "sub_command" do
      argument "foo"
      argument "bar"
      run do |opts, args|
      end
      sub "sub_sub_command" do
        argument "foo"
        argument "bar"
        argument "foo" # duplicate
        run do |opts, args|
        end
      end
    end
  end
end

MyCli.start(ARGV)
