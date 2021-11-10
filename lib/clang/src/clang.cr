require "./lib_clang"
require "./index"
require "./translation_unit"
require "./cursor"
require "./type"
require "./unsaved_file"
require "./source_location"

module Clang
  class Error < Exception
    alias Code = LibC::CXErrorCode

    def self.from(code : Code)
      new code.to_s
    end
  end

  # Make a `String` from a `LibC::CXString` then disposes the latter unless
  # *dispose* is false.
  def self.string(str : LibC::CXString, dispose = true)
    String.new(LibC.clang_getCString(str))
  ensure
    LibC.clang_disposeString(str) if dispose
  end

  def self.default_c_include_directories(cflags)
    program = ENV["CC"]? || "cc"
    args = {"-E", "-", "-v"}
    default_include_directories(program, args, cflags)
  end

  def self.default_cxx_include_directories(cflags)
    program = ENV["CXX"]? || "c++"
    args = {"-E", "-x", "c++", "-", "-v"}
    default_include_directories(program, args, cflags)
  end

  private def self.default_include_directories(program, args, cflags)
    Process.run(program, args, shell: true, error: io = IO::Memory.new)

    includes = [] of String
    found_include = false

    io.rewind.to_s.each_line do |line|
      if line.starts_with?("#include ")
        found_include = true
      elsif found_include
        line = line.lstrip
        break unless line.starts_with?('.') || line.starts_with?('/')
        includes << line.split(" (", 2)[0].chomp
      end
    end

    includes.reverse_each do |path|
      cflags.unshift "-I#{path}"
    end
  end
end
