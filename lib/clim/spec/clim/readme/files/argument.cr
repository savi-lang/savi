require "./../../../../src/clim"

class MyCli < Clim
  main do
    desc "argument sample"
    usage "command [options] [arguments]"

    option "--dummy=WORDS",
      desc: "dummy option"

    argument "first-arg",
      desc: "first argument!",
      type: String,
      default: "default value"

    argument "second-arg",
      desc: "second argument!",
      type: Int32,
      default: 999

    run do |opts, args|
      puts "typeof(args.first_arg)    => #{typeof(args.first_arg)}"
      puts "       args.first_arg     => #{args.first_arg}"
      puts "typeof(args.second_arg)   => #{typeof(args.second_arg)}"
      puts "       args.second_arg    => #{args.second_arg}"
      puts "typeof(args.all_args)     => #{typeof(args.all_args)}"
      puts "       args.all_args      => #{args.all_args}"
      puts "typeof(args.unknown_args) => #{typeof(args.unknown_args)}"
      puts "       args.unknown_args  => #{args.unknown_args}"
      puts "typeof(args.argv)         => #{typeof(args.argv)}"
      puts "       args.argv          => #{args.argv}"
    end
  end
end

MyCli.start(ARGV)
