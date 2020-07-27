require "./../../../../src/clim"

module Hello
  class Cli < Clim
    main do
      usage "hello <name>"
      option "--prefix <text>", type: String, desc: "Prefix.", required: true
      argument "arg1", type: String, desc: "argument1", required: true
      run do |opts, args|
        puts "ok"
      end
    end
  end
end

Hello::Cli.start(ARGV)
