require "./source_location"

module Clang
  struct Token
    Kind = LibC::CXKind

    def initialize(@translation_unit : TranslationUnit, @token : LibC::CXToken)
    end

    def kind
      LibC.clang_getTokenKind(self)
    end

    def spelling
      Clang.string(LibC.clang_getTokenSpelling(@translation_unit, self))
    end

    def location
      SourceLocation.new(LibC.clang_getTokenLocation(@translation_unit, self))
    end

    def extent
      LibC.clang_getTokenExtent(@translation_unit, self)
    end

    def to_unsafe
      @token
    end

    def inspect(io)
      io << "<##{self.class.name} kind="
      io << kind
      io << " spelling="
      io << spelling
      io << '>'
    end
  end
end
