module Clang
  enum TypeKind : UInt32
    Invalid = 0

    Unexposed = 1

    Void = 2
    Bool = 3
    Char_U = 4
    UChar = 5
    Char16 = 6
    Char32 = 7
    UShort = 8
    UInt = 9
    ULong = 10
    ULongLong = 11
    UInt128 = 12
    Char_S = 13
    SChar = 14
    WChar = 15
    Short = 16
    Int = 17
    Long = 18
    LongLong = 19
    Int128 = 20
    Float = 21
    Double = 22
    LongDouble = 23
    NullPtr = 24
    Overload = 25
    Dependent = 26
    ObjCId = 27
    ObjCClass = 28
    ObjCSel = 29
    Float128 = 30
    FirstBuiltin = Void
    LastBuiltin  = ObjCSel

    Complex = 100
    Pointer = 101
    BlockPointer = 102
    LValueReference = 103
    RValueReference = 104
    Record = 105
    Enum = 106
    Typedef = 107
    ObjCInterface = 108
    ObjCObjectPointer = 109
    FunctionNoProto = 110
    FunctionProto = 111
    ConstantArray = 112
    Vector = 113
    IncompleteArray = 114
    VariableArray = 115
    DependentSizedArray = 116
    MemberPointer = 117
    Auto = 118

    Elaborated = 119

    def spelling
      Clang.string(LibC.clang_getTypeKindSpelling(self))
    end

    def to_unsafe
      LibC::CXTypeKind.new(value)
    end
  end
end
