require "./token"

module Clang
  class TranslationUnit
    alias Options = LibC::CXTranslationUnit_Flags

    def self.default_options
      Options.new(LibC.clang_defaultEditingTranslationUnitOptions()) |
        Options::DetailedPreprocessingRecord
    end

    def self.from_pch(index, path)
      error_code = LibC.clang_createTranslationUnit2(index, path, out unit)
      raise Error.from(error_code) unless error_code.success?
      new(unit)
    end

    def self.from_source(index,
                         files : Array(UnsavedFile),
                         args = [] of String,
                         options = default_options,
                         filename = files[0].filename)
      error_code = LibC.clang_parseTranslationUnit2(
        index, filename,
        args.map(&.to_unsafe), args.size,
        files.map(&.to_unsafe), files.size,
        options, out unit)
      raise Error.from(error_code) unless error_code.success?
      new(unit)
    end

    def self.from_source_file(index, path, args = [] of String)
      new LibC.clang_createTranslationUnitFromSourceFile(index, path, args.size, args.map(&.to_unsafe), 0, nil)
    end

    protected def initialize(@unit : LibC::CXTranslationUnit)
      raise "invalid translation unit pointer" unless @unit
    end

    def finalize
      LibC.clang_disposeTranslationUnit(self)
    end

    def cursor
      Cursor.new LibC.clang_getTranslationUnitCursor(self)
    end

    def multiple_include_guarded?(file : File)
      LibC.clang_isFileMultipleIncludeGuarded(self, file) == 1
    end

    def tokenize(source_range, skip = 0)
      LibC.clang_tokenize(self, source_range, out tokens, out count)
      begin
        skip.upto(count - 1) do |index|
          yield Token.new(self, tokens[index])
        end
      ensure
        LibC.clang_disposeTokens(self, tokens, count)
      end
    end

    # NOTE: since clang 7+
    def get_token(location : SourceLocation)
      Token.new(LibC.clang_getToken(self, location))
    end

    def suspend
      LibC.clang_suspendTranslationUnit(self)
    end

    def to_unsafe
      @unit
    end
  end
end
