require "./type_kind"

module Clang
  struct Type
    # NOTE: since clang 8+
    alias NullabilityKind = LibC::CXTypeNullabilityKind

    def initialize(@type : LibC::CXType)
    end

    def kind
      TypeKind.new(@type.kind.value)
    end

    def spelling
      Clang.string(LibC.clang_getTypeSpelling(self))
    end

    def objc_type_encoding
      Clang.string(LibC.clang_Type_getObjCEncoding(self))
    end

    def canonical_type
      Type.new(LibC.clang_getCanonicalType(self))
    end

    def cursor
      Cursor.new(LibC.clang_getTypeDeclaration(self))
    end

    def const_qualified?
      LibC.clang_isConstQualifiedType(self) == 1
    end

    def volatile_qualified?
      LibC.clang_isVolatileQualifiedType(self) == 1
    end

    def restrict_qualified?
      LibC.clang_isRestrictQualifiedType(self) == 1
    end

    def pointee_type
      # TODO: restrict to Pointer, BlockPointer, ObjCObjectPointer, MemberPointer
      Type.new(LibC.clang_getPointeeType(self))
    end

    def calling_conv
      # TODO: restrict to FunctionProto, FunctionNoProto
      LibC.clang_getFunctionTypeCallingConv(self)
    end

    def result_type
      # TODO: restrict to FunctionProto, FunctionNoProto
      Type.new(LibC.clang_getResultType(self))
    end

    def arguments
      # TODO: restrict to FunctionProto, FunctionNoProto
      Array(Type).new(LibC.clang_getNumArgTypes(self)) do |i|
        Type.new(LibC.clang_getArgType(self, i))
      end
    end

    # NOTE: since clang 8+
    def objc_object_base_type
      Type.new(LibC.clang_Type_getObjCObjectBaseType(self))
    end

    # NOTE: since clang 8+
    def objc_protocol_declarations
      Array(Cursor).new(LibC.clang_Type_getNumObjCProtocolRefs(self)) do |i|
        Cursor.new(LibC.clang_Type_getObjCProtocolDecl(self, i))
      end
    end

    # NOTE: since clang 8+
    def objc_type_args
      Array(Type).new(LibC.clang_Type_getNumObjCTypeArgs(self)) do |i|
        Type.new(LibC.clang_Type_getObjCTypeArg(self, i))
      end
    end

    def variadic?
      # TODO: restrict to FunctionProto, FunctionNoProto
      LibC.clang_isFunctionTypeVariadic(self) == 1
    end

    def pod?
      LibC.clang_isPODType(self) == 1
    end

    def element_type
      Type.new(LibC.clang_getElementType(self))
    end

    def num_elements
      LibC.clang_getNumElements(self)
    end

    def array_element_type
      # TODO: restrict to ConstantArray, IncompleteArray, VariableArray, DependentSizedArray
      Type.new(LibC.clang_getArrayElementType(self))
    end

    def array_size
      # TODO: restrict to ConstantArray
      LibC.clang_getArraySize(self)
    end

    def named_type
      Type.new(LibC.clang_Type_getNamedType(self))
    end

    # NOTE: since clang 8+
    def nullability_kind
      LibC.clang_Type_getNullability(self)
    end

    def align_of
      LibC.clang_Type_getAlignOf(self)
    end

    def class_type
      Type.new(LibC.clang_Type_getClassType(self))
    end

    def size_of
      LibC.clang_Type_getSizeOf(self)
    end

    def offset_of(field_name)
      LibC.clang_Type_getOffsetOf(self, field_name)
    end

    # NOTE: since clang 8+
    def modified_type
      Type.new(LibC.clang_Type_getModifiedType(self))
    end

    def template_arguments
      # TODO: restrict to FunctionProto, FunctionNoProto
      Array(Type).new(LibC.clang_Type_getNumTemplateArguments(self)) do |i|
        Type.new(LibC.clang_Type_getTemplateArgumentAsType(self, i))
      end
    end

    def cxx_ref_qualifier
      # TODO: restrict to FunctionProto, FunctionNoProto
      LibC.clang_Type_getCXXRefQualifier(self)
    end

    def to_unsafe
      @type
    end

    def inspect(io)
      io << "<##{self.class.name} kind=#{kind} spelling=#{spelling}>"
    end

    def inspect(io)
      io << "<#"
      io << self.class.name
      io << " kind="
      io << kind
      io << " spelling="
      spelling.inspect(io)
      io << ">"
    end
  end
end
