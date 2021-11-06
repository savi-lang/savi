module Clang
  class EvalResult
    alias Kind = LibC::CXEvalResultKind

    def initialize(@result : LibC::CXEvalResult)
    end

    def kind
      LibC.clang_evalResult_getKind(self)
    end

    def as_int
      LibC.clang_evalResult_getAsInt(self)
    end

    def unsigned?
      LibC.clang_evalResult_isUnsignedInt(self) != 0
    end

    def as_unsigned
      LibC.clang_evalResult_getAsUnsigned(self)
    end

    def as_long_long
      LibC.clang_evalResult_getAsLongLong(self)
    end

    def as_double
      LibC.clang_evalResult_getAsDouble(self)
    end

    def as_str
      Clang.string(LibC.clang_evalResult_getAsStr(self))
    end

    def finalize
      LibC.clang_evalResult_dispose(self)
    end

    def to_unsafe
      @result
    end
  end
end
