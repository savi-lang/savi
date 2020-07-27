require "./spec_helper"

class IoCommand < Clim
  main do
    desc "main command."
    usage "main [sub_command] [arguments]"
    run do |opts, args, io|
      io.puts "in main"
    end
  end
end

class IoSubCommand < Clim
  main do
    run do |opts, args|
    end
    sub "sub_command" do
      desc "sub command."
      usage "sub_command [arguments]"
      run do |opts, args, io|
        io.puts "in sub_command"
      end
    end
  end
end

class IoSubSubCommand < Clim
  main do
    run do |opts, args|
    end
    sub "sub_command" do
      run do |opts, args|
      end
      sub "sub_sub_command" do
        run do |opts, args, io|
          io.puts "in sub_sub_command"
        end
      end
    end
  end
end

describe Clim do
  describe "#start" do
    it "with IO::Memory in main command" do
      io = IO::Memory.new
      IoCommand.start([] of String, io: io)
      io.to_s.should eq "in main\n"
    end
    it "with IO::Memory in sub command" do
      io = IO::Memory.new
      IoSubCommand.start(["sub_command"], io: io)
      io.to_s.should eq "in sub_command\n"
    end
    it "with IO::Memory in sub sub command" do
      io = IO::Memory.new
      IoSubSubCommand.start(["sub_command", "sub_sub_command"], io: io)
      io.to_s.should eq "in sub_sub_command\n"
    end
  end
end
