lib LibC
  # LLVM_CLANG_C_DOCUMENTATION_H = 
  struct CXComment
    ast_node : Void*
    translation_unit : CXTranslationUnit
  end
  fun clang_Cursor_getParsedComment(CXCursor) : CXComment
  enum CXCommentKind : UInt
    Null = 0
    Text = 1
    InlineCommand = 2
    HTMLStartTag = 3
    HTMLEndTag = 4
    Paragraph = 5
    BlockCommand = 6
    ParamCommand = 7
    TParamCommand = 8
    VerbatimBlockCommand = 9
    VerbatimBlockLine = 10
    VerbatimLine = 11
    FullComment = 12
  end
  enum CXCommentInlineCommandRenderKind : UInt
    Normal = 0
    Bold = 1
    Monospaced = 2
    Emphasized = 3
  end
  enum CXCommentParamPassDirection : UInt
    In = 0
    Out = 1
    InOut = 2
  end
  fun clang_Comment_getKind(CXComment) : CXCommentKind
  fun clang_Comment_getNumChildren(CXComment) : UInt
  fun clang_Comment_getChild(CXComment, UInt) : CXComment
  fun clang_Comment_isWhitespace(CXComment) : UInt
  fun clang_InlineContentComment_hasTrailingNewline(CXComment) : UInt
  fun clang_TextComment_getText(CXComment) : CXString
  fun clang_InlineCommandComment_getCommandName(CXComment) : CXString
  fun clang_InlineCommandComment_getRenderKind(CXComment) : CXCommentInlineCommandRenderKind
  fun clang_InlineCommandComment_getNumArgs(CXComment) : UInt
  fun clang_InlineCommandComment_getArgText(CXComment, UInt) : CXString
  fun clang_HTMLTagComment_getTagName(CXComment) : CXString
  fun clang_HTMLStartTagComment_isSelfClosing(CXComment) : UInt
  fun clang_HTMLStartTag_getNumAttrs(CXComment) : UInt
  fun clang_HTMLStartTag_getAttrName(CXComment, UInt) : CXString
  fun clang_HTMLStartTag_getAttrValue(CXComment, UInt) : CXString
  fun clang_BlockCommandComment_getCommandName(CXComment) : CXString
  fun clang_BlockCommandComment_getNumArgs(CXComment) : UInt
  fun clang_BlockCommandComment_getArgText(CXComment, UInt) : CXString
  fun clang_BlockCommandComment_getParagraph(CXComment) : CXComment
  fun clang_ParamCommandComment_getParamName(CXComment) : CXString
  fun clang_ParamCommandComment_isParamIndexValid(CXComment) : UInt
  fun clang_ParamCommandComment_getParamIndex(CXComment) : UInt
  fun clang_ParamCommandComment_isDirectionExplicit(CXComment) : UInt
  fun clang_ParamCommandComment_getDirection(CXComment) : CXCommentParamPassDirection
  fun clang_TParamCommandComment_getParamName(CXComment) : CXString
  fun clang_TParamCommandComment_isParamPositionValid(CXComment) : UInt
  fun clang_TParamCommandComment_getDepth(CXComment) : UInt
  fun clang_TParamCommandComment_getIndex(CXComment, UInt) : UInt
  fun clang_VerbatimBlockLineComment_getText(CXComment) : CXString
  fun clang_VerbatimLineComment_getText(CXComment) : CXString
  fun clang_HTMLTagComment_getAsString(CXComment) : CXString
  fun clang_FullComment_getAsHTML(CXComment) : CXString
  fun clang_FullComment_getAsXML(CXComment) : CXString
end
