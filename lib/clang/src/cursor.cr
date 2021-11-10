require "./cursor_kind"
require "./eval_result"
require "./platform_availability"
require "./printing_policy"

module Clang
  alias ChildVisitResult = LibC::CXChildVisitResult
  alias Linkage = LibC::CXLinkageKind
  alias Availability = LibC::CXAvailabilityKind
  alias Visibility = LibC::CXVisibilityKind
  alias Language = LibC::CXLanguageKind
  alias CXXAccessSpecifier = LibC::CX_CXXAccessSpecifier
  alias StorageClass = LibC::CX_StorageClass

  struct Cursor
    def initialize(@cursor : LibC::CXCursor)
    end

    def ==(other : Cursor)
      LibC.clang_equalCursors(self, other) != 0
    end

    def ==(other)
      false
    end

    def kind
      CursorKind.new(@cursor.kind.value)
    end

    def type
      Type.new(LibC.clang_getCursorType(self))
    end

    def visit_children(&block : Cursor -> ChildVisitResult)
      LibC.clang_visitChildren(self, ->(cursor, parent, data) {
        proc = Box(typeof(block)).unbox(data)
        proc.call(Cursor.new(cursor))
      }, Box.box(block))
    end

    def has_attributes?
      LibC.clang_Cursor_hasAttrs(self) == 1
    end

    def language
      LibC.clang_getCursorLanguage(self)
    end

    def hash
      LibC.clang_hashCursor(self)
    end

    # NOTE: since clang 7+
    def invalid_declaration?
      LibC.clang_isInvalidDeclaration(self) == 1
    end

    def linkage
      LibC.clang_getCursorLinkage(self)
    end

    def visibility
      LibC.clang_getCursorVisibility(self)
    end

    def availability
      LibC.clang_getCursorAvailability(self)
    end

    def platform_availability
      LibC.clang_getCursorPlatformAvailability(self, nil, nil, nil, nil, out availability, out size)
      Array(PlatformAvailability).new(size).new { |i| PlatformAvailability.new(availability[i]) }
    end

    def semantic_parent
      Cursor.new LibC.clang_getCursorSemanticParent(self)
    end

    def lexical_parent
      Cursor.new LibC.clang_getCursorLexicalParent(self)
    end

    # def included_file
    #   File.new(LibC.clang_getIncludedFile(self))
    # end

    def location
      SourceLocation.new(LibC.clang_getCursorLocation(self))
    end

    def extent
      LibC.clang_getCursorExtent(self)
    end

    def overriden_cursors
      LibC.clang_getOverriddenCursors(self, out overriden, out size)
      Array(Cursor).new(size) { |i| Cursor.new(overriden[i]) }
    ensure
      LibC.clang_disposeOverriddenCursors(overriden) if overriden
    end

    def typedef_decl_underlying_type
      Type.new(LibC.clang_getTypedefDeclUnderlyingType(self))
    end

    def enum_decl_integer_type
      Type.new(LibC.clang_getEnumDeclIntegerType(self))
    end

    def enum_constant_decl_value
      raise ArgumentError.new("error: cursor is #{kind} not EnumConstantDecl") unless kind.enum_constant_decl?
      LibC.clang_getEnumConstantDeclValue(self)
    end

    def enum_constant_decl_unsigned_value
      raise ArgumentError.new("error: cursor is #{kind} not EnumConstantDecl") unless kind.enum_constant_decl?
      LibC.clang_getEnumConstantDeclUnsignedValue(self)
    end

    def field_decl_bit_width
      LibC.clang_getFieldDeclBitWidth(self)
    end

    def arguments
      Array(Cursor).new(LibC.clang_Cursor_getNumArguments(self)) do |i|
        Cursor.new(LibC.clang_Cursor_getArgument(self, i))
      end
    end

    # def template_arguments
    #   Array(???).new(LibC.clang_Cursor_getNumTemplateArguments(self)) do |i|
    #     case LibC.clang_Cursor_getTemplateArgumentKind(self, i)
    #     when .null?
    #     when .type?
    #     when .declaration?
    #     when .null_ptr?
    #     when .integral?
    #     when .template_expansion?
    #     when .expression?
    #     when .pack?
    #     when .invalid?
    #     end
    #   end
    # end

    def macro_function_like?
      LibC.clang_Cursor_isMacroFunctionLike(self) == 1
    end

    def macro_builtin?
      LibC.clang_Cursor_isMacroBuiltin(self) == 1
    end

    def function_inlined?
      LibC.clang_Cursor_isFunctionInlined(self) == 1
    end

    def objc_type_encoding
      Clang.string(LibC.clang_getDeclObjCTypeEncoding(self))
    end

    def result_type
      Type.new(LibC.clang_getCursorResultType(self))
    end

    def offset_of_field
      LibC.clang_Cursor_getOffsetOfField(self)
    end

    def anonymous?
      LibC.clang_Cursor_isAnonymous(self) == 1
    end

    def bit_field?
      LibC.clang_Cursor_isBitField(self) == 1
    end

    def virtual_base?
      LibC.clang_isVirtualBase(self) == 1
    end

    def cxx_access_specifier
      LibC.clang_getCXXAccessSpecifier(self)
    end

    def storage_class
      LibC.clang_Cursor_getStorageClass(self)
    end

    def overloads
      Array(Cursor).new(LibC.clang_getNumOverloadedDecls(self)).new do |i|
        Cursor.new(LibC.clang_getOverloadedDecl(self, i))
      end
    end

    def ib_outlet_collection_type
      Type.new(LibC.clang_getIBOutletCollectionType(self))
    end


    # TODO: C++ AST introspection (lib_clang/ast.cr)



    # CROSS REFERENCING

    # Returns a raw `LibC::CXString`, use `Clang.string(usr, dispose: false)`
    # to get a String.
    def usr
      LibC.clang_getCursorUSR(self)
    end

    # USR constructors return a raw `LibC::CXString`, use
    # `Clang.string(usr, dispose: false)` to get a String.
    module USR
      def self.objc_class(name)
        LibC.clang_constructUSR_ObjCClass(name)
      end

      def self.objc_category(class_name, category_name)
        LibC.clang_constructUSR_ObjCCategory(class_name, category_name)
      end

      def self.objc_protocol(name)
        LibC.clang_constructUSR_ObjCProtocol(name)
      end

      def self.objc_ivar(name, class_usr : LibC::CXString)
        LibC.clang_constructUSR_ObjCIvar(name, class_usr)
      end

      def self.objc_method(name, instance, class_usr : LibC::CXString)
        LibC.clang_constructUSR_ObjCMethod(name, instance ? 1 : 0, class_usr)
      end

      def self.objc_property(name, class_usr : LibC::CXString)
        LibC.clang_constructUSR_ObjCProperty(property, class_usr)
      end
    end

    def spelling
      Clang.string(LibC.clang_getCursorSpelling(self))
    end

    # def spelling_name_range(piece_index, options = 0)
    #   SourceRange.new(LibC.clang_Cursor_getSpellingNameRange(self, piece_index, options))
    # end

    def display_name
      Clang.string(LibC.clang_getCursorDisplayName(self))
    end

    def referenced
      Cursor.new(LibC.clang_getCursorReferenced(self))
    end

    def definition?
      if LibC.clang_isCursorDefinition(self) == 1
        definition
      end
    end

    def definition
      Cursor.new(LibC.clang_getCursorDefinition(self))
    end

    def canonical_cursor
      Cursor.new(LibC.clang_getCanonicalCursor(self))
    end

    def objc_selector_index
      clang_Cursor_getObjCSelectorIndex(self)
    end

    def dynamic_call?
      LibC.clang_Cursor_isDynamicCall(self) == 1
    end

    def receiver_type
      Type.new(LibC.clang_Cursor_getReceiverType(self))
    end

    def objc_property_attributes
      LibC.clang_Cursor_getObjCPropertyAttributes(self, 0)
    end

    # NOTE: since clang 8+
    def objc_property_getter_name
      Clang.string LibC.clang_Cursor_getObjCPropertyGetterName(self)
    end

    # NOTE: since clang 8+
    def objc_property_setter_name
      Clang.string LibC.clang_Cursor_getObjCPropertySetterName(self)
    end

    # def comment_range
    #   SourceRange.new(LibC.clang_Cursor_getCommentRange(self))
    # end

    def raw_comment_text
      Clang.string(LibC.clang_Cursor_getRawCommentText(self))
    end

    def brief_comment_text
      Clang.string(LibC.clang_Cursor_getBriefCommentText(self))
    end

    def objc_decl_qualifiers
      LibC.clang_Cursor_getObjCDeclQualifiers(self)
    end

    def objc_optional?
      LibC.clang_Cursor_isObjCOptional(self) == 1
    end

    def variadic?
      LibC.clang_Cursor_isVariadic(self) == 1
    end

    # def comment_range?
    #   SourceRange.new(LibC.clang_Cursor_getCommentRange(self))
    # end

    def evaluate
      if ptr = LibC.clang_Cursor_Evaluate(self)
        EvalResult.new(ptr)
      end
    end

    def mangling
      Clang.string(LibC.clang_Cursor_getMangling(self))
    end

    def cxx_manglings
      if list = LibC.clang_Cursor_getCXXManglings(self)
        Array(String).new(list.value.count) do |i|
          Clang.string(list.value.strings[i], dispose: false)
        end
      end
    ensure
      LibC.clang_disposeStringSet(list) if list
    end

    def objc_manglings
      if list = LibC.clang_Cursor_getObjCManglings(self)
        Array(String).new(list.value.count) do |i|
          Clang.string(list.value.strings[i], dispose: false)
        end
      end
    ensure
      LibC.clang_disposeStringSet(list) if list
    end

    def printing_policy
      PrintingPolicy.new(LibC.clang_getCursorPrintingPolicy(self))
    end

    def pretty_printed(printing_policy : PrintingPolicy)
      Clang.string(LibC.clang_getCursorPrettyPrinted(self, printing_policy))
    end

    def inspect(io)
      io << "<#"
      io << self.class.name
      io << " kind="
      kind.to_s(io)

      case kind
      when .cxx_access_specifier?
        io << "access=" << cxx_access_specifier
      else
        io << " spelling="
        spelling.inspect(io)
        io << " type="
        type.inspect(io)
      end

      io << ">"
    end

    def to_unsafe
      @cursor
    end
  end
end
