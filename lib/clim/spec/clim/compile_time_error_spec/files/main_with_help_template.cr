require "./../../../../src/clim"

class MyCli < Clim
  main do
    help_template do |desc, usage, options, arguments, sub_commands|
      <<-MY_HELP

        command description: #{desc}
        command usage: #{usage}

        options:
      #{options.map(&.[](:help_line)).join("\n")}

        arguments:
      #{arguments.map(&.[](:help_line)).join("\n")}

        sub_commands:
      #{sub_commands.map(&.[](:help_line)).join("\n")}


      MY_HELP
    end
    argument "arg1", type: String, desc: "argument1"
    argument "arg2", type: String, desc: "argument2"
    run do |opts, args|
    end
    sub "sub_command" do
      desc "sub_comand."
      option "-n NUM", type: Int32, desc: "Number.", default: 0
      argument "sub-arg1", type: Bool, desc: "sub-argument1"
      argument "sub-arg2", type: Bool, desc: "sub-argument2"
      run do |opts, args|
      end
      sub "sub_sub_command" do
        desc "sub_sub_comand description."
        option "-p PASSWORD", type: String, desc: "Password.", required: true
        argument "sub-sub-arg1", type: Int32, desc: "sub sub argument1"
        argument "sub-sub-arg2", type: Int32, desc: "sub sub argument2"
        run do |opts, args|
        end
      end
    end
  end
end

MyCli.start(ARGV)
