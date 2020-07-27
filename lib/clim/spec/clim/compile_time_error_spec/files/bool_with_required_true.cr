require "./../../../../src/clim"

class MyCli < Clim
  main do
    desc "main command."
    option "-b", type: Bool, desc: "your bool.", required: true
    run do |options, arguments|
    end
  end
end

MyCli.start(ARGV)
