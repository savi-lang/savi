require "./../../../../src/clim"

class MyCli < Clim
  main do
    run do |opts, args|
    end
    sub "sub_command" do
      help_template do |desc, usage, options, sub_commands|
        <<-MY_HELP

          command description: #{desc}
          command usage: #{usage}

          options:
        #{options.map(&.[](:help_line)).join("\n")}

          sub_commands:
        #{sub_commands.map(&.[](:help_line)).join("\n")}


        MY_HELP
      end
      desc "sub_comand."
      option "-n NUM", type: Int32, desc: "Number.", default: 0
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
