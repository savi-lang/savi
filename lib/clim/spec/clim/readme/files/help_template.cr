require "./../../../../src/clim"

class MyCli < Clim
  main do
    help_template do |desc, usage, options, arguments, sub_commands|
      options_help_lines = options.map do |option|
        option[:names].join(", ") + "\n" + "    #{option[:desc]}"
      end
      arguments_help_lines = arguments.map do |argument|
        ("%02d: " % [argument[:sequence_number]]) +
          argument[:display_name] +
          "\n" +
          "      #{argument[:desc]}"
      end

      base = <<-BASE_HELP
      #{usage}

      #{desc}

      options:
      #{options_help_lines.join("\n")}

      arguments:
      #{arguments_help_lines.join("\n")}

      BASE_HELP

      sub = <<-SUB_COMMAND_HELP

      sub commands:
      #{sub_commands.map(&.[](:help_line)).join("\n")}
      SUB_COMMAND_HELP

      sub_commands.empty? ? base : base + sub
    end
    desc "Your original command line interface tool."
    usage <<-USAGE
    usage: my_cli [--version] [--help] [-P PORT|--port=PORT]
                  [-h HOST|--host=HOST] [-p PASSWORD|--password=PASSWORD] [arguments]
    USAGE
    version "version 1.0.0"
    option "-P PORT", "--port=PORT", type: Int32, desc: "Port number.", default: 3306
    option "-h HOST", "--host=HOST", type: String, desc: "Host name.", default: "localhost"
    option "-p PASSWORD", "--password=PASSWORD", type: String, desc: "Password."
    argument "image_name", type: String, desc: "The name of your favorite docker image."
    argument "container_id", type: String, desc: "The ID of the running container."
    run do |opts, args|
    end
    sub "sub_command" do
      desc "my_cli's sub_comand."
      run do |opts, args|
      end
    end
  end
end

MyCli.start(ARGV)
