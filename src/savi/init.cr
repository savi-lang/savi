require "file_utils"

module Savi::Init
  module Lib
    def self.run(name : String) : Bool
      unless /\A[A-Z][\w\d]*\z/ =~ name
        STDERR.puts "Please name your library using a valid type name, " +
          "starting with an uppercase letter."
        return false
      end

      Init.with_files([
        {"manifest.savi", [
          ":manifest lib #{name}",
          "  :sources \"src/*.savi\"",
          "",
          ":manifest bin \"spec\"",
          "  :copies #{name}",
          "  :sources \"spec/*.savi\"",
          "",
          "  :dependency Spec v0",
          "    :from \"github:savi-lang/Spec\"",
          "    :depends on Map",
          "",
          "  :transitive dependency Map v0",
          "    :from \"github:savi-lang/Map\"",
          "",
        ].join("\n")},

        {"src/#{name}.savi", [
          ":module #{name}",
          "  :fun placeholder",
          "    True",
          "",
        ].join("\n")},

        {"spec/Main.savi", [
          ":actor Main",
          "  :new (env Env)",
          "    Spec.Process.run(env, [",
          "      Spec.Run(#{name}.Spec).new(env)",
          "    ])",
          "",
        ].join("\n")},

        {"spec/#{name}.Spec.savi", [
          ":class #{name}.Spec",
          "  :is Spec",
          "  :const describes: \"#{name}\"",
          "",
          "  :it \"has a placeholder method for demonstrating testing\"",
          "    assert: #{name}.placeholder == True",
          "",
        ].join("\n")},
      ])
    end
  end

  module Bin
    def self.run(name : String) : Bool
      Init.with_files([
        {"manifest.savi", [
          ":manifest bin #{name.inspect}",
          "  :sources \"src/*.savi\"",
          "",
        ].join("\n")},

        {"src/Main.savi", [
          ":actor Main",
          "  :new (env Env)",
          "    env.out.print(\"Hello, World!\")",
          "",
        ].join("\n")},
      ])
    end
  end

  def self.with_files(files : Array({String, String})) : Bool
    existing_names = files.map(&.first).select { |name| File.exists?(name) }
    case existing_names.size
    when 0
      files.each { |name, content|
        puts "Creating #{name}"
        FileUtils.mkdir_p(File.dirname(name))
        File.write(name, content)
      }
      true
    when 1
      STDERR.puts "A file named #{existing_names.first.inspect} already exists."
      STDERR.puts
      STDERR.puts "Please delete it before continuing."
      false
    else
      STDERR.puts "The following files already exist:"
      existing_names.each { |name| STDERR.puts "- #{name}"}
      STDERR.puts
      STDERR.puts "Please delete them before continuing."
      false
    end
  end
end