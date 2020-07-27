# clim

"clim" is slim command line interface builder for Crystal.

_"clim" = "cli" + "slim"_

[![Build Status](https://travis-ci.org/at-grandpa/clim.svg?branch=master)](https://travis-ci.org/at-grandpa/clim)

## TOC

- [Goals](#goals)
- [Support](#support)
- [Installation](#installation)
- [Samples](#samples)
  - [Minimum sample](#minimum-sample)
  - [Command information sample](#command-information-sample)
  - [Sub commands sample](#sub-commands-sample)
- [How to use](#how-to-use)
  - [require & inherit](#require--inherit)
  - [Command Informations](#command-informations)
    - [desc](#desc)
    - [usage](#usage)
    - [alias_name](#alias_name)
    - [version](#version)
    - [Short option for help](#short-option-for-help)
    - [option](#option)
    - [argument](#argument)
    - [help_template](#help_template)
  - [help string](#help-string)
  - [`io` in run block](#io-in-run-block)
- [Development](#development)
- [Contributing](#contributing)
- [Contributors](#contributors)

## Goals

* Slim implementation.
* Intuitive code.

## Support

- [x] Option types
  - [x] `Int8`
  - [x] `Int16`
  - [x] `Int32`
  - [x] `Int64`
  - [x] `UInt8`
  - [x] `UInt16`
  - [x] `UInt32`
  - [x] `UInt64`
  - [x] `Float32`
  - [x] `Float64`
  - [x] `String`
  - [x] `Bool`
  - [x] `Array(Int8)`
  - [x] `Array(Int16)`
  - [x] `Array(Int32)`
  - [x] `Array(Int64)`
  - [x] `Array(UInt8)`
  - [x] `Array(UInt16)`
  - [x] `Array(UInt32)`
  - [x] `Array(UInt64)`
  - [x] `Array(Float32)`
  - [x] `Array(Float64)`
  - [x] `Array(String)`
- [x] Argument types
  - [x] `Int8`
  - [x] `Int16`
  - [x] `Int32`
  - [x] `Int64`
  - [x] `UInt8`
  - [x] `UInt16`
  - [x] `UInt32`
  - [x] `UInt64`
  - [x] `Float32`
  - [x] `Float64`
  - [x] `String`
  - [x] `Bool`
- [x] Default values for option & argument
- [x] Required flag for option & argument
- [x] Nested sub commands
- [x] `--help` option
- [x] Customizable help message
- [x] `version` macro
- [x] Command name alias


## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  clim:
    github: at-grandpa/clim
    version: 0.13.0
```

## Samples

### Minimum sample

*src/minimum.cr*

```crystal
require "clim"

class MyCli < Clim
  main do
    run do |opts, args|
      puts "#{args.all_args.join(", ")}!"
    end
  end
end

MyCli.start(ARGV)
```

```console
$ crystal build -o ./minimum src/minimum.cr
$ ./minimum foo bar baz
foo, bar, baz!
```

### Command information sample

*src/hello.cr*

```crystal
require "clim"

module Hello
  class Cli < Clim
    main do
      desc "Hello CLI tool."
      usage "hello [options] [arguments] ..."
      version "Version 0.1.0"
      option "-g WORDS", "--greeting=WORDS", type: String, desc: "Words of greetings.", default: "Hello"
      argument "first_member", type: String, desc: "first member name.", default: "member1"
      argument "second_member", type: String, desc: "second member name.", default: "member2"
      run do |opts, args|
        print "#{opts.greeting}, "
        print "#{args.first_member} & #{args.second_member} !\n"
        print "And #{args.unknown_args.join(", ")} !"
        print "\n"
      end
    end
  end
end

Hello::Cli.start(ARGV)
```

```console
$ crystal build src/hello.cr
$ ./hello --help

  Hello CLI tool.

  Usage:

    hello [options] [arguments] ...

  Options:

    -g WORDS, --greeting=WORDS       Words of greetings. [type:String] [default:"Hello"]
    --help                           Show this help.
    --version                        Show version.

  Arguments:

    01. first_member       first member name. [type:String] [default:"member1"]
    02. second_member      second member name. [type:String] [default:"member2"]

$ ./hello -g 'Good night' Ichiro Miko Takashi Taro
Good night, Ichiro & Miko !
And Takashi, Taro !
```

### Sub commands sample

*src/fake-crystal-command.cr*

```crystal
require "clim"

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
```

Build and run.

```console
$ crystal build -o ./fcrystal src/fake-crystal-command.cr
$ ./fcrystal

  Fake Crystal command.

  Usage:

    fcrystal [sub_command] [arguments]

  Options:

    --help                           Show this help.

  Sub Commands:

    tool   run a tool
    spec   build and run specs

```

Show sub command help.

```console
$ ./fcrystal tool --help

  run a tool

  Usage:

    fcrystal tool [tool] [arguments]

  Options:

    --help                           Show this help.

  Sub Commands:

    format   format project, directories and/or files

```

Run sub sub command.

```console
$ ./fcrystal tool format
Fake Crystal tool format!!
```

## How to use

### require & inherit

```crystal
require "clim"

class MyCli < Clim

  # ...

end
```

### Command Informations

#### desc

Description of the command. It is displayed in Help.

```crystal
class MyCli < Clim
  main do
    desc "My Command Line Interface."
    run do |opts, args|
      # ...
    end
  end
end
```

#### usage

Usage of the command. It is displayed in Help.

```crystal
class MyCli < Clim
  main do
    usage  "mycli [sub-command] [options] ..."
    run do |opts, args|
      # ...
    end
  end
end
```

#### alias_name

An alias for the command. It can be specified only for subcommand.

```crystal
require "clim"

class MyCli < Clim
  main do
    run do |opts, args|
      # ...
    end
    sub "sub" do
      alias_name  "alias1", "alias2"
      run do |opts, args|
        puts "sub_command run!!"
      end
    end
  end
end

MyCli.start(ARGV)
```

```console
$ ./mycli sub
sub_command run!!
$ ./mycli alias1
sub_command run!!
$ ./mycli alias2
sub_command run!!
```

#### version

You can specify the string to be displayed with `--version`.

```crystal
require "clim"

class MyCli < Clim
  main do
    version "mycli version: 1.0.1"
    run do |opts, args|
      # ...
    end
  end
end

MyCli.start(ARGV)
```

```console
$ ./mycli --version
mycli version: 1.0.1
```

If you want to display it even with `-v`, add ` short: "-v" `.

```crystal
require "clim"

class MyCli < Clim
  main do
    version "mycli version: 1.0.1", short: "-v"
    run do |opts, args|
      # ...
    end
  end
end

MyCli.start(ARGV)
```

```console
$ ./mycli --version
mycli version: 1.0.1
$ ./mycli -v
mycli version: 1.0.1
```

#### Short option for help

The short help option is not set by default. If you want help to appear by specifying `-h` , specify `help short: "-h"` .

(However, it should not conflict with other options.)

```crystal
require "clim"

class MyCli < Clim
  main do
    desc "help directive test."
    usage "mycli [options] [arguments]"
    help short: "-h"
    run do |opts, args|
      # ...
    end
  end
end

MyCli.start(ARGV)
```

```console
$ ./mycli -h

  help directive test.

  Usage:

    mycli [options] [arguments]

  Options:

    -h, --help                       Show this help.

$ ./mycli --help

  help directive test.

  Usage:

    mycli [options] [arguments]

  Options:

    -h, --help                       Show this help.

```

In addition to `-h`, you can specify any single character. For example, `help short: "-a"` .

#### option

You can specify multiple options for the command.

 | Argument        | Description        | Example                       | Required | Default                 |
 | --------------- | ------------------ | ----------------------------- | -------- | ----------------------- |
 | First argument  | short or long name | `-t TIMES`, `--times TIMES`   | true     | -                       |
 | Second argument | long name          | `--times TIMES`               | false    | -                       |
 | `type`          | option type        | `type: Array(Float32)`        | false    | `String`                |
 | `desc`          | option description | `desc: "option description."` | false    | `"Option description."` |
 | `default`       | default value      | `default: [1.1_f32, 2.2_f32]` | false    | `nil`                   |
 | `required`      | required flag      | `required: true`              | false    | `false`                 |

```crystal
class MyCli < Clim
  main do
    option "--greeting=WORDS", desc: "Words of greetings.", default: "Hello"
    option "-n NAME", "--name=NAME", type: Array(String), desc: "Target name.", default: ["Taro"]
    run do |opts, args|
      puts typeof(opts.greeting) # => String
      puts typeof(opts.name)     # => Array(String)
    end
  end
end
```

The type of the option is determined by the `default` and `required` patterns.

*Number*

For example `Int8`.

 | `default` | `required` | Type                                    |
 | --------- | ---------- | --------------------------------------- |
 | exist     | `true`     | `Int8` (default: Your specified value.) |
 | exist     | `false`    | `Int8` (default: Your specified value.) |
 | not exist | `true`     | `Int8`                                  |
 | not exist | `false`    | `Int8 \| Nil`                           |

*String*

 | `default` | `required` | Type                                      |
 | --------- | ---------- | ----------------------------------------- |
 | exist     | `true`     | `String` (default: Your specified value.) |
 | exist     | `false`    | `String` (default: Your specified value.) |
 | not exist | `true`     | `String`                                  |
 | not exist | `false`    | `String \| Nil`                           |

*Bool*

 | `default` | `required` | Type                                    |
 | --------- | ---------- | --------------------------------------- |
 | exist     | `true`     | `Bool` (default: Your specified value.) |
 | exist     | `false`    | `Bool` (default: Your specified value.) |
 | not exist | `true`     | `Bool`                                  |
 | not exist | `false`    | `Bool` (default: `false`)               |

*Array*

 | `default` | `required` | Type                                        |
 | --------- | ---------- | ------------------------------------------- |
 | exist     | `true`     | `Array(T)` (default: Your specified value.) |
 | exist     | `false`    | `Array(T)` (default: Your specified value.) |
 | not exist | `true`     | `Array(T)`                                  |
 | not exist | `false`    | `Array(T)` (default: `[] of T`)             |

For Bool, you do not need to specify arguments for short or long.

```crystal
class MyCli < Clim
  main do
    option "-v", "--verbose", type: Bool, desc: "Verbose."
    run do |opts, args|
      puts typeof(opts.verbose) # => Bool
    end
  end
end
```

Option method names are long name if there is a long, and short name if there is only a short. Also, hyphens are replaced by underscores.

```crystal
class MyCli < Clim
  main do
    option "-n", type: String, desc: "name."  # => short name only.
    option "--my-age", type: Int32, desc: "age." # => long name only.
    run do |opts, args|
      puts typeof(opts.n)      # => (String | Nil)
      puts typeof(opts.my_age) # => (Int32 | Nil)
    end
  end
end
```

#### argument

You can specify multiple arguments for the command.

 | Argument        | Description          | Example                         | Required | Default                   |
 | --------------- | -------------------- | ------------------------------- | -------- | ------------------------- |
 | First argument  | name                 | `my_argument`                   | true     | -                         |
 | `type`          | argument type        | `type: String`                  | false    | `String`                  |
 | `desc`          | argument description | `desc: "argument description."` | false    | `"Argument description."` |
 | `default`       | default value        | `default: "default value"`      | false    | `nil`                     |
 | `required`      | required flag        | `required: true`                | false    | `false`                   |

The order of the arguments is related to the order in which they are defined. Also, when calling a method, hyphens in the method name of the argument are converted to underscores. There are also `all_args`, `unknown_args` and `argv` methods.

```crystal
require "clim"

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

```

```console
$ crystal run src/argument.cr -- --help

  argument sample

  Usage:

    command [options] [arguments]

  Options:

    --dummy=WORDS                    dummy option [type:String]
    --help                           Show this help.

  Arguments:

    01. first-arg       first argument! [type:String] [default:"default value"]
    02. second-arg      second argument! [type:Int32] [default:999]

$ crystal run src/argument.cr -- 000 111 --dummy dummy_words 222 333
typeof(args.first_arg)    => String
       args.first_arg     => 000
typeof(args.second_arg)   => Int32
       args.second_arg    => 111
typeof(args.all_args)     => Array(String)
       args.all_args      => ["000", "111", "222", "333"]
typeof(args.unknown_args) => Array(String)
       args.unknown_args  => ["222", "333"]
typeof(args.argv)         => Array(String)
       args.argv          => ["000", "111", "--dummy", "dummy_words", "222", "333"]

```

The type of the arguments is determined by the `default` and `required` patterns.

*Number*

For example `Int8`.

 | `default` | `required` | Type                                    |
 | --------- | ---------- | --------------------------------------- |
 | exist     | `true`     | `Int8` (default: Your specified value.) |
 | exist     | `false`    | `Int8` (default: Your specified value.) |
 | not exist | `true`     | `Int8`                                  |
 | not exist | `false`    | `Int8 \| Nil`                           |

*String*

 | `default` | `required` | Type                                      |
 | --------- | ---------- | ----------------------------------------- |
 | exist     | `true`     | `String` (default: Your specified value.) |
 | exist     | `false`    | `String` (default: Your specified value.) |
 | not exist | `true`     | `String`                                  |
 | not exist | `false`    | `String \| Nil`                           |

*Bool*

 | `default` | `required` | Type                                    |
 | --------- | ---------- | --------------------------------------- |
 | exist     | `true`     | `Bool` (default: Your specified value.) |
 | exist     | `false`    | `Bool` (default: Your specified value.) |
 | not exist | `true`     | `Bool`                                  |
 | not exist | `false`    | `Bool \| Nil`                           |

### help_template

You can customize the help message by `help_template` block. It must be placed in main block. Also it needs to return `String`. Block arguments are `desc : String`, `usage : String`, `options : HelpOptionsType`, `argments : HelpArgumentsType` and `sub_commands : HelpSubCommandsType`.

*help_template_test.cr*

```crystal
require "clim"

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
```

```console
$ crystal run src/help_template_test.cr -- --help
usage: my_cli [--version] [--help] [-P PORT|--port=PORT]
              [-h HOST|--host=HOST] [-p PASSWORD|--password=PASSWORD] [arguments]

Your original command line interface tool.

options:
-P PORT, --port=PORT
    Port number.
-h HOST, --host=HOST
    Host name.
-p PASSWORD, --password=PASSWORD
    Password.
--help
    Show this help.
--version
    Show version.

arguments:
01: image_name
      The name of your favorite docker image.
02: container_id
      The ID of the running container.

sub commands:
    sub_command   my_cli's sub_comand.

```

options:

```crystal
# `options` type
alias HelpOptionsType = Array(NamedTuple(
    names:     Array(String),
    type:      Int8.class | Int32.class | ... | String.class | Bool.clsss, # => Support Types
    desc:      String,
    default:   Int8 | Int32 | ... | String | Bool, # => Support Types,
    required:  Bool,
    help_line: String
))

# `options` example
[
  {
    names:     ["-g WORDS", "--greeting=WORDS"],
    type:      String,
    desc:      "Words of greetings.",
    default:   "Hello",
    required:  false,
    help_line: "    -g WORDS, --greeting=WORDS       Words of greetings. [type:String] [default:\"Hello\"]",
  },
  {
    names:     ["-n NAME"],
    type:      Array(String),
    desc:      "Target name.",
    default:   ["Taro"],
    required:  true,
    help_line: "    -n NAME                          Target name. [type:Array(String)] [default:[\"Taro\"]] [required]",
  },
  {
    names:     ["--help"],
    type:      Bool,
    desc:      "Show this help.",
    default:   false,
    required:  false,
    help_line: "    --help                           Show this help.",
  },
]
```
arguments:

```crystal
# `arguments` type
alias HelpArgumentsType = Array(NamedTuple(
    method_name:     String,
    display_name:    String,
    type:            Int8.class | Int32.class | ... | String.class | Bool.clsss, # => Support Types
    desc:            String,
    default:         Int8 | Int32 | ... | String | Bool, # => Support Types,
    required:        Bool,
    sequence_number: Int32,
    help_line:       String
))

# `arguments` example
[
  {
    method_name:     "argument1",
    display_name:    "argument1",
    type:            String,
    desc:            "first argument.",
    default:         "default value",
    required:        true,
    sequence_number: 1,
    help_line:       "    01. argument1            first argument. [type:String] [default:\"default value\"] [required]",
  },
  {
    method_name:     "argument2foo",
    display_name:    "argument2foo",
    type:            Int32,
    desc:            "second argument.",
    default:         1,
    required:        false,
    sequence_number: 2,
    help_line:       "    02. argument2foo         second argument. [type:Int32] [default:1]",
  },
]
```

sub_commands:

```crystal
# `sub_commands` type
alias HelpSubCommandsType = Array(NamedTuple(
    names:     Array(String),
    desc:      String,
    help_line: String
))

# `sub_commands` example
[
  {
    names:     ["abc", "def", "ghi"],
    desc:      "abc command.",
    help_line: "    abc, def, ghi            abc command.",
  },
  {
    names:     ["abcdef", "ghijkl", "mnopqr"],
    desc:      "abcdef command.",
    help_line: "    abcdef, ghijkl, mnopqr   abcdef command.",
  },
]
```

### help string

```crystal
class MyCli < Clim
  main do
    run do |opts, args|
      opts.help_string # => help string
    end
  end
end
```

### `io` in run block

You can receive `io` in a run block by passing it as the second argument to the start method.

```crystal
require "clim"

class IoCommand < Clim
  main do
    run do |opts, args, io|
      io.puts "in main"
    end
  end
end

io = IO::Memory.new
IoCommand.start([] of String, io: io)
puts io.to_s # => "in main\n"
```

## Development

```
$ make spec
```

## Contributing

1. Fork it ( https://github.com/at-grandpa/clim/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [at-grandpa](https://github.com/at-grandpa) - creator, maintainer
