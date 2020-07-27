require "./../../../../src/clim"

class MyCli < Clim
  main do
    run do |opts, args|
    end
    sub "sub_command" do
      desc "sub_comand."
      option "-n NUM", type: Int32, desc: "Number.", default: 0
      argument "arg1", type: Bool, desc: "argument1"
      run do |opts, args|
      end
      sub "sub_sub_command" do
        desc "sub_sub_comand description."
        option "-p PASSWORD", type: String, desc: "Password.", required: true
        run do |opts, args|
        end
      end
    end
  end
end

MyCli.start(ARGV)
