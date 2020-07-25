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
        run do |opts, args|
        end
      end
    end
    sub "sub_command_2" do
      argument "foo"
      argument "bar"
      argument "foo" # deplicate
      run do |opts, args|
      end
    end
  end
end

MyCli.start(ARGV)
