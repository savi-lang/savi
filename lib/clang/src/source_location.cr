require "./file"

module Clang
  struct SourceLocation
    def initialize(@location : LibC::CXSourceLocation)
    end

    def ==(other : SourceLocation)
      LibC.clang_equalLocations(self, other) != 0
    end

    def in_system_header?
      LibC.clang_location_isInSystemHeader(self) == 1
    end

    def from_main_file?
      LibC.clang_location_isFromMainFile(self) == 1
    end

    def file_location
      LibC.clang_getFileLocation(self, out file, out line, out column, out offset)
      {file ? File.new(file) : nil, line, column, offset}
    end

    def file_name
      LibC.clang_getFileLocation(self, out file, nil, nil, nil)
      Clang.string(LibC.clang_getFileName(file)) if file
    end

    def spelling_location
      LibC.clang_getSpellingLocation(self, out file, out line, out column, out offset)
      {file ? File.new(file) : nil, line, column, offset}
    end

    def expansion_location
      LibC.clang_getExpansionLocation(self, out file, out line, out column, out offset)
      {file ? File.new(file) : nil, line, column, offset}
    end

    def instantiation_location
      LibC.clang_getInstantiationLocation(self, out file, out line, out column, out offset)
      {file ? File.new(file) : nil, line, column, offset}
    end

    def presumed_location
      LibC.clang_getPresumedLocation(self, out file, out line, out column, out offset)
      {file ? File.new(file) : nil, line, column, offset}
    end

    def to_unsafe
      @location
    end

    def inspect(io)
      io << "<##{self.class.name} "
      to_s(io)
      io << ">"
    end

    def to_s(io)
      file, line, column, _ = file_location
      io << (file.try(&.name) || "??") << ' ' << line << ':' << column
    end
  end
end
