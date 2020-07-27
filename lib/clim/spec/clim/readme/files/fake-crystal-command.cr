require "./../../../../src/clim"

module FakeCrystalCommand
  class Cli < Clim
    main do
      desc "Fake Crystal command."
      usage "fcrystal [sub_command] [arguments]"
      run do |opts, args|
        puts opts.help_string # => help string.
      end
      sub "tool" do
        desc "run a tool"
        usage "fcrystal tool [tool] [arguments]"
        run do |opts, args|
          puts "Fake Crystal tool!!"
        end
        sub "format" do
          desc "format project, directories and/or files"
          usage "fcrystal tool format [options] [file or directory]"
          run do |opts, args|
            puts "Fake Crystal tool format!!"
          end
        end
      end
      sub "spec" do
        desc "build and run specs"
        usage "fcrystal spec [options] [files]"
        run do |opts, args|
          puts "Fake Crystal spec!!"
        end
      end
    end
  end
end

FakeCrystalCommand::Cli.start(ARGV)
