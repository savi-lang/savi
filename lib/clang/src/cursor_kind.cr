enum LibC::CXCursorKind
  def declaration?
    LibC.clang_isDeclaration(self) == 1
  end

  def reference?
    LibC.clang_isReference(self) == 1
  end

  def expression?
    LibC.clang_isExpression(self) == 1
  end

  def statement?
    LibC.clang_isStatement(self) == 1
  end

  def attribute?
    LibC.clang_isAttribute(self) == 1
  end

  def invalid?
    LibC.clang_isInvalid(self) == 1
  end

  def translation_unit?
    LibC.clang_isTranslationUnit(self) == 1
  end

  def preprocessing?
    LibC.clang_isPreprocessing(self) == 1
  end

  def unexposed?
    LibC.clang_isUnexposed(self) == 1
  end

  def spelling
    Clang.string LibC.clang_getCursorKindSpelling(self)
  end
end

module Clang
  alias CursorKind = LibC::CXCursorKind
end
