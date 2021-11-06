require "./c2cr/parser"

cflags = [] of String
header = nil
remove_enum_prefix = remove_enum_suffix = false

if arg = ENV["CFLAGS"]?
  cflags += arg.split(' ').reject(&.empty?)
end

i = -1
while arg = ARGV[i += 1]?
  case arg
  when "-I", "-D"
    if value = ARGV[i += 1]?
      cflags << value
    else
      abort "fatal : missing value for #{arg}"
    end
  when .starts_with?("-I"), .starts_with?("-D")
    cflags << arg
  when .ends_with?(".h")
    header = arg

  when "--remove-enum-prefix"
    remove_enum_prefix = true
  when .starts_with?("--remove-enum-prefix=")
    case value = arg[21..-1]
    when "", "false" then remove_enum_prefix = false
    when "true" then remove_enum_prefix = true
    else remove_enum_prefix = value
    end

  when "--remove-enum-suffix"
    remove_enum_suffix = true
  when .starts_with?("--remove-enum-suffix=")
    case value = arg[21..-1]
    when "", "false" then remove_enum_suffix = false
    when "true" then remove_enum_suffix = true
    else remove_enum_suffix = value
    end

  when "--help"
    STDERR.puts <<-EOF
    usage : c2cr [--help] [options] <header.h>

    Some available options are:
        -I<directory>   Adds directory to search path for include files
        -D<name>        Adds an implicit #define

    In addition, the CFLAGS environment variable will be used, so you may set it
    up before compilation when search directories, defines, and other options
    aren't fixed and can be dynamic.

    The following options control how enum constants are cleaned up. By default
    the value is false (no cleanup), whereas true will remove matching patterns,
    while a fixed value will remove just that:
        --remove-enum-prefix[=true,false,<value>]
        --remove-enum-suffix[=true,false,<value>]
    EOF
    exit 0

  else
    abort "Unknown option: #{arg}"
  end
end

Clang.default_c_include_directories(cflags)

unless header
  abort "fatal : no header to create bindings for."
end

parser = C2CR::Parser.new(
  header,
  cflags,
  remove_enum_prefix: remove_enum_prefix,
  remove_enum_suffix: remove_enum_suffix,
)

puts "lib LibC"
parser.parse
puts "end"
