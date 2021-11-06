lib LibC
  # LLVM_CLANG_C_INDEX_H = 
  CINDEX_VERSION_MAJOR = 0
  CINDEX_VERSION_MINOR = 50
  # CINDEX_VERSION_ENCODE = ( major, minor)((( major)*10000)+(( minor)*1))
  # CINDEX_VERSION = CINDEX_VERSION_ENCODE( CINDEX_VERSION_MAJOR, CINDEX_VERSION_MINOR)
  # CINDEX_VERSION_STRINGIZE_ = ( major, minor)
  # CINDEX_VERSION_STRINGIZE = ( major, minor) CINDEX_VERSION_STRINGIZE_( major, minor)
  # CINDEX_VERSION_STRING = CINDEX_VERSION_STRINGIZE( CINDEX_VERSION_MAJOR, CINDEX_VERSION_MINOR)
  alias CXIndex = Void*
  type CXTargetInfoImpl = Void
  alias CXTargetInfo = CXTargetInfoImpl*
  type CXTranslationUnitImpl = Void
  alias CXTranslationUnit = CXTranslationUnitImpl*
  alias CXClientData = Void*
  struct CXUnsavedFile
    filename : Char*
    contents : Char*
    length : ULong
  end
  enum CXAvailabilityKind : UInt
    Available = 0
    Deprecated = 1
    NotAvailable = 2
    NotAccessible = 3
  end
  struct CXVersion
    major : Int
    minor : Int
    subminor : Int
  end
  enum CXCursor_ExceptionSpecificationKind : UInt
    None = 0
    DynamicNone = 1
    Dynamic = 2
    MSAny = 3
    BasicNoexcept = 4
    ComputedNoexcept = 5
    Unevaluated = 6
    Uninstantiated = 7
    Unparsed = 8
  end
  fun clang_createIndex(Int, Int) : CXIndex
  fun clang_disposeIndex(CXIndex) : Void
  enum CXGlobalOptFlags : UInt
    None = 0
    ThreadBackgroundPriorityForIndexing = 1
    ThreadBackgroundPriorityForEditing = 2
    ThreadBackgroundPriorityForAll = 3
  end
  fun clang_CXIndex_setGlobalOptions(CXIndex, UInt) : Void
  fun clang_CXIndex_getGlobalOptions(CXIndex) : UInt
  fun clang_CXIndex_setInvocationEmissionPathOption(CXIndex, Char*) : Void
  alias CXFile = Void*
  fun clang_getFileName(CXFile) : CXString
  fun clang_getFileTime(CXFile) : TimeT
  struct CXFileUniqueID
    data : StaticArray(ULongLong, 3)
  end
  fun clang_getFileUniqueID(CXFile, CXFileUniqueID*) : Int
  fun clang_isFileMultipleIncludeGuarded(CXTranslationUnit, CXFile) : UInt
  fun clang_getFile(CXTranslationUnit, Char*) : CXFile
  fun clang_getFileContents(CXTranslationUnit, CXFile, SizeT*) : Char*
  fun clang_File_isEqual(CXFile, CXFile) : Int
  fun clang_File_tryGetRealPathName(CXFile) : CXString
  struct CXSourceLocation
    ptr_data : StaticArray(Void*, 2)
    int_data : UInt
  end
  struct CXSourceRange
    ptr_data : StaticArray(Void*, 2)
    begin_int_data : UInt
    end_int_data : UInt
  end
  fun clang_getNullLocation() : CXSourceLocation
  fun clang_equalLocations(CXSourceLocation, CXSourceLocation) : UInt
  fun clang_getLocation(CXTranslationUnit, CXFile, UInt, UInt) : CXSourceLocation
  fun clang_getLocationForOffset(CXTranslationUnit, CXFile, UInt) : CXSourceLocation
  fun clang_Location_isInSystemHeader(CXSourceLocation) : Int
  fun clang_Location_isFromMainFile(CXSourceLocation) : Int
  fun clang_getNullRange() : CXSourceRange
  fun clang_getRange(CXSourceLocation, CXSourceLocation) : CXSourceRange
  fun clang_equalRanges(CXSourceRange, CXSourceRange) : UInt
  fun clang_Range_isNull(CXSourceRange) : Int
  fun clang_getExpansionLocation(CXSourceLocation, CXFile*, UInt*, UInt*, UInt*) : Void
  fun clang_getPresumedLocation(CXSourceLocation, CXString*, UInt*, UInt*) : Void
  fun clang_getInstantiationLocation(CXSourceLocation, CXFile*, UInt*, UInt*, UInt*) : Void
  fun clang_getSpellingLocation(CXSourceLocation, CXFile*, UInt*, UInt*, UInt*) : Void
  fun clang_getFileLocation(CXSourceLocation, CXFile*, UInt*, UInt*, UInt*) : Void
  fun clang_getRangeStart(CXSourceRange) : CXSourceLocation
  fun clang_getRangeEnd(CXSourceRange) : CXSourceLocation
  struct CXSourceRangeList
    count : UInt
    ranges : CXSourceRange*
  end
  fun clang_getSkippedRanges(CXTranslationUnit, CXFile) : CXSourceRangeList*
  fun clang_getAllSkippedRanges(CXTranslationUnit) : CXSourceRangeList*
  fun clang_disposeSourceRangeList(CXSourceRangeList*) : Void
  enum CXDiagnosticSeverity : UInt
    Ignored = 0
    Note = 1
    Warning = 2
    Error = 3
    Fatal = 4
  end
  alias CXDiagnostic = Void*
  alias CXDiagnosticSet = Void*
  fun clang_getNumDiagnosticsInSet(CXDiagnosticSet) : UInt
  fun clang_getDiagnosticInSet(CXDiagnosticSet, UInt) : CXDiagnostic
  enum CXLoadDiag_Error : UInt
    None = 0
    Unknown = 1
    CannotLoad = 2
    InvalidFile = 3
  end
  fun clang_loadDiagnostics(Char*, CXLoadDiag_Error*, CXString*) : CXDiagnosticSet
  fun clang_disposeDiagnosticSet(CXDiagnosticSet) : Void
  fun clang_getChildDiagnostics(CXDiagnostic) : CXDiagnosticSet
  fun clang_getNumDiagnostics(CXTranslationUnit) : UInt
  fun clang_getDiagnostic(CXTranslationUnit, UInt) : CXDiagnostic
  fun clang_getDiagnosticSetFromTU(CXTranslationUnit) : CXDiagnosticSet
  fun clang_disposeDiagnostic(CXDiagnostic) : Void
  enum CXDiagnosticDisplayOptions : UInt
    SourceLocation = 1
    Column = 2
    SourceRanges = 4
    Option = 8
    CategoryId = 16
    CategoryName = 32
  end
  fun clang_formatDiagnostic(CXDiagnostic, UInt) : CXString
  fun clang_defaultDiagnosticDisplayOptions() : UInt
  fun clang_getDiagnosticSeverity(CXDiagnostic) : CXDiagnosticSeverity
  fun clang_getDiagnosticLocation(CXDiagnostic) : CXSourceLocation
  fun clang_getDiagnosticSpelling(CXDiagnostic) : CXString
  fun clang_getDiagnosticOption(CXDiagnostic, CXString*) : CXString
  fun clang_getDiagnosticCategory(CXDiagnostic) : UInt
  fun clang_getDiagnosticCategoryName(UInt) : CXString
  fun clang_getDiagnosticCategoryText(CXDiagnostic) : CXString
  fun clang_getDiagnosticNumRanges(CXDiagnostic) : UInt
  fun clang_getDiagnosticRange(CXDiagnostic, UInt) : CXSourceRange
  fun clang_getDiagnosticNumFixIts(CXDiagnostic) : UInt
  fun clang_getDiagnosticFixIt(CXDiagnostic, UInt, CXSourceRange*) : CXString
  fun clang_getTranslationUnitSpelling(CXTranslationUnit) : CXString
  fun clang_createTranslationUnitFromSourceFile(CXIndex, Char*, Int, Char**, UInt, CXUnsavedFile*) : CXTranslationUnit
  fun clang_createTranslationUnit(CXIndex, Char*) : CXTranslationUnit
  fun clang_createTranslationUnit2(CXIndex, Char*, CXTranslationUnit*) : CXErrorCode
  enum CXTranslationUnit_Flags : UInt
    None = 0
    DetailedPreprocessingRecord = 1
    Incomplete = 2
    PrecompiledPreamble = 4
    CacheCompletionResults = 8
    ForSerialization = 16
    CXXChainedPCH = 32
    SkipFunctionBodies = 64
    IncludeBriefCommentsInCodeCompletion = 128
    CreatePreambleOnFirstParse = 256
    KeepGoing = 512
    SingleFileParse = 1024
    LimitSkipFunctionBodiesToPreamble = 2048
    IncludeAttributedTypes = 4096
    VisitImplicitAttributes = 8192
  end
  fun clang_defaultEditingTranslationUnitOptions() : UInt
  fun clang_parseTranslationUnit(CXIndex, Char*, Char**, Int, CXUnsavedFile*, UInt, UInt) : CXTranslationUnit
  fun clang_parseTranslationUnit2(CXIndex, Char*, Char**, Int, CXUnsavedFile*, UInt, UInt, CXTranslationUnit*) : CXErrorCode
  fun clang_parseTranslationUnit2FullArgv(CXIndex, Char*, Char**, Int, CXUnsavedFile*, UInt, UInt, CXTranslationUnit*) : CXErrorCode
  enum CXSaveTranslationUnit_Flags : UInt
    None = 0
  end
  fun clang_defaultSaveOptions(CXTranslationUnit) : UInt
  enum CXSaveError : UInt
    None = 0
    Unknown = 1
    TranslationErrors = 2
    InvalidTU = 3
  end
  fun clang_saveTranslationUnit(CXTranslationUnit, Char*, UInt) : Int
  fun clang_suspendTranslationUnit(CXTranslationUnit) : UInt
  fun clang_disposeTranslationUnit(CXTranslationUnit) : Void
  enum CXReparse_Flags : UInt
    None = 0
  end
  fun clang_defaultReparseOptions(CXTranslationUnit) : UInt
  fun clang_reparseTranslationUnit(CXTranslationUnit, UInt, CXUnsavedFile*, UInt) : Int
  enum CXTUResourceUsageKind : UInt
    AST = 1
    Identifiers = 2
    Selectors = 3
    GlobalCompletionResults = 4
    SourceManagerContentCache = 5
    AST_SideTables = 6
    SourceManager_Membuffer_Malloc = 7
    SourceManager_Membuffer_MMap = 8
    ExternalASTSource_Membuffer_Malloc = 9
    ExternalASTSource_Membuffer_MMap = 10
    Preprocessor = 11
    PreprocessingRecord = 12
    SourceManager_DataStructures = 13
    Preprocessor_HeaderSearch = 14
    MEMORY_IN_BYTES_BEGIN = 1
    MEMORY_IN_BYTES_END = 14
    First = 1
    Last = 14
  end
  fun clang_getTUResourceUsageName(CXTUResourceUsageKind) : Char*
  struct CXTUResourceUsageEntry
    kind : CXTUResourceUsageKind
    amount : ULong
  end
  struct CXTUResourceUsage
    data : Void*
    num_entries : UInt
    entries : CXTUResourceUsageEntry*
  end
  fun clang_getCXTUResourceUsage(CXTranslationUnit) : CXTUResourceUsage
  fun clang_disposeCXTUResourceUsage(CXTUResourceUsage) : Void
  fun clang_getTranslationUnitTargetInfo(CXTranslationUnit) : CXTargetInfo
  fun clang_TargetInfo_dispose(CXTargetInfo) : Void
  fun clang_TargetInfo_getTriple(CXTargetInfo) : CXString
  fun clang_TargetInfo_getPointerWidth(CXTargetInfo) : Int
  enum CXCursorKind : UInt
    UnexposedDecl = 1
    StructDecl = 2
    UnionDecl = 3
    ClassDecl = 4
    EnumDecl = 5
    FieldDecl = 6
    EnumConstantDecl = 7
    FunctionDecl = 8
    VarDecl = 9
    ParmDecl = 10
    ObjCInterfaceDecl = 11
    ObjCCategoryDecl = 12
    ObjCProtocolDecl = 13
    ObjCPropertyDecl = 14
    ObjCIvarDecl = 15
    ObjCInstanceMethodDecl = 16
    ObjCClassMethodDecl = 17
    ObjCImplementationDecl = 18
    ObjCCategoryImplDecl = 19
    TypedefDecl = 20
    CXXMethod = 21
    Namespace = 22
    LinkageSpec = 23
    Constructor = 24
    Destructor = 25
    ConversionFunction = 26
    TemplateTypeParameter = 27
    NonTypeTemplateParameter = 28
    TemplateTemplateParameter = 29
    FunctionTemplate = 30
    ClassTemplate = 31
    ClassTemplatePartialSpecialization = 32
    NamespaceAlias = 33
    UsingDirective = 34
    UsingDeclaration = 35
    TypeAliasDecl = 36
    ObjCSynthesizeDecl = 37
    ObjCDynamicDecl = 38
    CXXAccessSpecifier = 39
    FirstDecl = 1
    LastDecl = 39
    FirstRef = 40
    ObjCSuperClassRef = 40
    ObjCProtocolRef = 41
    ObjCClassRef = 42
    TypeRef = 43
    CXXBaseSpecifier = 44
    TemplateRef = 45
    NamespaceRef = 46
    MemberRef = 47
    LabelRef = 48
    OverloadedDeclRef = 49
    VariableRef = 50
    LastRef = 50
    FirstInvalid = 70
    InvalidFile = 70
    NoDeclFound = 71
    NotImplemented = 72
    InvalidCode = 73
    LastInvalid = 73
    FirstExpr = 100
    UnexposedExpr = 100
    DeclRefExpr = 101
    MemberRefExpr = 102
    CallExpr = 103
    ObjCMessageExpr = 104
    BlockExpr = 105
    IntegerLiteral = 106
    FloatingLiteral = 107
    ImaginaryLiteral = 108
    StringLiteral = 109
    CharacterLiteral = 110
    ParenExpr = 111
    UnaryOperator = 112
    ArraySubscriptExpr = 113
    BinaryOperator = 114
    CompoundAssignOperator = 115
    ConditionalOperator = 116
    CStyleCastExpr = 117
    CompoundLiteralExpr = 118
    InitListExpr = 119
    AddrLabelExpr = 120
    StmtExpr = 121
    GenericSelectionExpr = 122
    GNUNullExpr = 123
    CXXStaticCastExpr = 124
    CXXDynamicCastExpr = 125
    CXXReinterpretCastExpr = 126
    CXXConstCastExpr = 127
    CXXFunctionalCastExpr = 128
    CXXTypeidExpr = 129
    CXXBoolLiteralExpr = 130
    CXXNullPtrLiteralExpr = 131
    CXXThisExpr = 132
    CXXThrowExpr = 133
    CXXNewExpr = 134
    CXXDeleteExpr = 135
    UnaryExpr = 136
    ObjCStringLiteral = 137
    ObjCEncodeExpr = 138
    ObjCSelectorExpr = 139
    ObjCProtocolExpr = 140
    ObjCBridgedCastExpr = 141
    PackExpansionExpr = 142
    SizeOfPackExpr = 143
    LambdaExpr = 144
    ObjCBoolLiteralExpr = 145
    ObjCSelfExpr = 146
    OMPArraySectionExpr = 147
    ObjCAvailabilityCheckExpr = 148
    FixedPointLiteral = 149
    LastExpr = 149
    FirstStmt = 200
    UnexposedStmt = 200
    LabelStmt = 201
    CompoundStmt = 202
    CaseStmt = 203
    DefaultStmt = 204
    IfStmt = 205
    SwitchStmt = 206
    WhileStmt = 207
    DoStmt = 208
    ForStmt = 209
    GotoStmt = 210
    IndirectGotoStmt = 211
    ContinueStmt = 212
    BreakStmt = 213
    ReturnStmt = 214
    GCCAsmStmt = 215
    AsmStmt = 215
    ObjCAtTryStmt = 216
    ObjCAtCatchStmt = 217
    ObjCAtFinallyStmt = 218
    ObjCAtThrowStmt = 219
    ObjCAtSynchronizedStmt = 220
    ObjCAutoreleasePoolStmt = 221
    ObjCForCollectionStmt = 222
    CXXCatchStmt = 223
    CXXTryStmt = 224
    CXXForRangeStmt = 225
    SEHTryStmt = 226
    SEHExceptStmt = 227
    SEHFinallyStmt = 228
    MSAsmStmt = 229
    NullStmt = 230
    DeclStmt = 231
    OMPParallelDirective = 232
    OMPSimdDirective = 233
    OMPForDirective = 234
    OMPSectionsDirective = 235
    OMPSectionDirective = 236
    OMPSingleDirective = 237
    OMPParallelForDirective = 238
    OMPParallelSectionsDirective = 239
    OMPTaskDirective = 240
    OMPMasterDirective = 241
    OMPCriticalDirective = 242
    OMPTaskyieldDirective = 243
    OMPBarrierDirective = 244
    OMPTaskwaitDirective = 245
    OMPFlushDirective = 246
    SEHLeaveStmt = 247
    OMPOrderedDirective = 248
    OMPAtomicDirective = 249
    OMPForSimdDirective = 250
    OMPParallelForSimdDirective = 251
    OMPTargetDirective = 252
    OMPTeamsDirective = 253
    OMPTaskgroupDirective = 254
    OMPCancellationPointDirective = 255
    OMPCancelDirective = 256
    OMPTargetDataDirective = 257
    OMPTaskLoopDirective = 258
    OMPTaskLoopSimdDirective = 259
    OMPDistributeDirective = 260
    OMPTargetEnterDataDirective = 261
    OMPTargetExitDataDirective = 262
    OMPTargetParallelDirective = 263
    OMPTargetParallelForDirective = 264
    OMPTargetUpdateDirective = 265
    OMPDistributeParallelForDirective = 266
    OMPDistributeParallelForSimdDirective = 267
    OMPDistributeSimdDirective = 268
    OMPTargetParallelForSimdDirective = 269
    OMPTargetSimdDirective = 270
    OMPTeamsDistributeDirective = 271
    OMPTeamsDistributeSimdDirective = 272
    OMPTeamsDistributeParallelForSimdDirective = 273
    OMPTeamsDistributeParallelForDirective = 274
    OMPTargetTeamsDirective = 275
    OMPTargetTeamsDistributeDirective = 276
    OMPTargetTeamsDistributeParallelForDirective = 277
    OMPTargetTeamsDistributeParallelForSimdDirective = 278
    OMPTargetTeamsDistributeSimdDirective = 279
    LastStmt = 279
    TranslationUnit = 300
    FirstAttr = 400
    UnexposedAttr = 400
    IBActionAttr = 401
    IBOutletAttr = 402
    IBOutletCollectionAttr = 403
    CXXFinalAttr = 404
    CXXOverrideAttr = 405
    AnnotateAttr = 406
    AsmLabelAttr = 407
    PackedAttr = 408
    PureAttr = 409
    ConstAttr = 410
    NoDuplicateAttr = 411
    CUDAConstantAttr = 412
    CUDADeviceAttr = 413
    CUDAGlobalAttr = 414
    CUDAHostAttr = 415
    CUDASharedAttr = 416
    VisibilityAttr = 417
    DLLExport = 418
    DLLImport = 419
    NSReturnsRetained = 420
    NSReturnsNotRetained = 421
    NSReturnsAutoreleased = 422
    NSConsumesSelf = 423
    NSConsumed = 424
    ObjCException = 425
    ObjCNSObject = 426
    ObjCIndependentClass = 427
    ObjCPreciseLifetime = 428
    ObjCReturnsInnerPointer = 429
    ObjCRequiresSuper = 430
    ObjCRootClass = 431
    ObjCSubclassingRestricted = 432
    ObjCExplicitProtocolImpl = 433
    ObjCDesignatedInitializer = 434
    ObjCRuntimeVisible = 435
    ObjCBoxable = 436
    FlagEnum = 437
    LastAttr = 437
    PreprocessingDirective = 500
    MacroDefinition = 501
    MacroExpansion = 502
    MacroInstantiation = 502
    InclusionDirective = 503
    FirstPreprocessing = 500
    LastPreprocessing = 503
    ModuleImportDecl = 600
    TypeAliasTemplateDecl = 601
    StaticAssert = 602
    FriendDecl = 603
    FirstExtraDecl = 600
    LastExtraDecl = 603
    OverloadCandidate = 700
  end
  struct CXCursor
    kind : CXCursorKind
    xdata : Int
    data : StaticArray(Void*, 3)
  end
  fun clang_getNullCursor() : CXCursor
  fun clang_getTranslationUnitCursor(CXTranslationUnit) : CXCursor
  fun clang_equalCursors(CXCursor, CXCursor) : UInt
  fun clang_Cursor_isNull(CXCursor) : Int
  fun clang_hashCursor(CXCursor) : UInt
  fun clang_getCursorKind(CXCursor) : CXCursorKind
  fun clang_isDeclaration(CXCursorKind) : UInt
  fun clang_isInvalidDeclaration(CXCursor) : UInt
  fun clang_isReference(CXCursorKind) : UInt
  fun clang_isExpression(CXCursorKind) : UInt
  fun clang_isStatement(CXCursorKind) : UInt
  fun clang_isAttribute(CXCursorKind) : UInt
  fun clang_Cursor_hasAttrs(CXCursor) : UInt
  fun clang_isInvalid(CXCursorKind) : UInt
  fun clang_isTranslationUnit(CXCursorKind) : UInt
  fun clang_isPreprocessing(CXCursorKind) : UInt
  fun clang_isUnexposed(CXCursorKind) : UInt
  enum CXLinkageKind : UInt
    Invalid = 0
    NoLinkage = 1
    Internal = 2
    UniqueExternal = 3
    External = 4
  end
  fun clang_getCursorLinkage(CXCursor) : CXLinkageKind
  enum CXVisibilityKind : UInt
    Invalid = 0
    Hidden = 1
    Protected = 2
    Default = 3
  end
  fun clang_getCursorVisibility(CXCursor) : CXVisibilityKind
  fun clang_getCursorAvailability(CXCursor) : CXAvailabilityKind
  struct CXPlatformAvailability
    platform : CXString
    introduced : CXVersion
    deprecated : CXVersion
    obsoleted : CXVersion
    unavailable : Int
    message : CXString
  end
  fun clang_getCursorPlatformAvailability(CXCursor, Int*, CXString*, Int*, CXString*, CXPlatformAvailability*, Int) : Int
  fun clang_disposeCXPlatformAvailability(CXPlatformAvailability*) : Void
  enum CXLanguageKind : UInt
    Invalid = 0
    C = 1
    ObjC = 2
    CPlusPlus = 3
  end
  fun clang_getCursorLanguage(CXCursor) : CXLanguageKind
  enum CXTLSKind : UInt
    None = 0
    Dynamic = 1
    Static = 2
  end
  fun clang_getCursorTLSKind(CXCursor) : CXTLSKind
  fun clang_Cursor_getTranslationUnit(CXCursor) : CXTranslationUnit
  type CXCursorSetImpl = Void
  alias CXCursorSet = CXCursorSetImpl*
  fun clang_createCXCursorSet() : CXCursorSet
  fun clang_disposeCXCursorSet(CXCursorSet) : Void
  fun clang_CXCursorSet_contains(CXCursorSet, CXCursor) : UInt
  fun clang_CXCursorSet_insert(CXCursorSet, CXCursor) : UInt
  fun clang_getCursorSemanticParent(CXCursor) : CXCursor
  fun clang_getCursorLexicalParent(CXCursor) : CXCursor
  fun clang_getOverriddenCursors(CXCursor, CXCursor**, UInt*) : Void
  fun clang_disposeOverriddenCursors(CXCursor*) : Void
  fun clang_getIncludedFile(CXCursor) : CXFile
  fun clang_getCursor(CXTranslationUnit, CXSourceLocation) : CXCursor
  fun clang_getCursorLocation(CXCursor) : CXSourceLocation
  fun clang_getCursorExtent(CXCursor) : CXSourceRange
  enum CXTypeKind : UInt
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
    Half = 31
    Float16 = 32
    ShortAccum = 33
    Accum = 34
    LongAccum = 35
    UShortAccum = 36
    UAccum = 37
    ULongAccum = 38
    FirstBuiltin = 2
    LastBuiltin = 38
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
    Pipe = 120
    OCLImage1dRO = 121
    OCLImage1dArrayRO = 122
    OCLImage1dBufferRO = 123
    OCLImage2dRO = 124
    OCLImage2dArrayRO = 125
    OCLImage2dDepthRO = 126
    OCLImage2dArrayDepthRO = 127
    OCLImage2dMSAARO = 128
    OCLImage2dArrayMSAARO = 129
    OCLImage2dMSAADepthRO = 130
    OCLImage2dArrayMSAADepthRO = 131
    OCLImage3dRO = 132
    OCLImage1dWO = 133
    OCLImage1dArrayWO = 134
    OCLImage1dBufferWO = 135
    OCLImage2dWO = 136
    OCLImage2dArrayWO = 137
    OCLImage2dDepthWO = 138
    OCLImage2dArrayDepthWO = 139
    OCLImage2dMSAAWO = 140
    OCLImage2dArrayMSAAWO = 141
    OCLImage2dMSAADepthWO = 142
    OCLImage2dArrayMSAADepthWO = 143
    OCLImage3dWO = 144
    OCLImage1dRW = 145
    OCLImage1dArrayRW = 146
    OCLImage1dBufferRW = 147
    OCLImage2dRW = 148
    OCLImage2dArrayRW = 149
    OCLImage2dDepthRW = 150
    OCLImage2dArrayDepthRW = 151
    OCLImage2dMSAARW = 152
    OCLImage2dArrayMSAARW = 153
    OCLImage2dMSAADepthRW = 154
    OCLImage2dArrayMSAADepthRW = 155
    OCLImage3dRW = 156
    OCLSampler = 157
    OCLEvent = 158
    OCLQueue = 159
    OCLReserveID = 160
    ObjCObject = 161
    ObjCTypeParam = 162
    Attributed = 163
    OCLIntelSubgroupAVCMcePayload = 164
    OCLIntelSubgroupAVCImePayload = 165
    OCLIntelSubgroupAVCRefPayload = 166
    OCLIntelSubgroupAVCSicPayload = 167
    OCLIntelSubgroupAVCMceResult = 168
    OCLIntelSubgroupAVCImeResult = 169
    OCLIntelSubgroupAVCRefResult = 170
    OCLIntelSubgroupAVCSicResult = 171
    OCLIntelSubgroupAVCImeResultSingleRefStreamout = 172
    OCLIntelSubgroupAVCImeResultDualRefStreamout = 173
    OCLIntelSubgroupAVCImeSingleRefStreamin = 174
    OCLIntelSubgroupAVCImeDualRefStreamin = 175
  end
  enum CXCallingConv : UInt
    Default = 0
    C = 1
    X86StdCall = 2
    X86FastCall = 3
    X86ThisCall = 4
    X86Pascal = 5
    AAPCS = 6
    AAPCS_VFP = 7
    X86RegCall = 8
    IntelOclBicc = 9
    Win64 = 10
    X86_64Win64 = 10
    X86_64SysV = 11
    X86VectorCall = 12
    Swift = 13
    PreserveMost = 14
    PreserveAll = 15
    AArch64VectorCall = 16
    Invalid = 100
    Unexposed = 200
  end
  struct CXType
    kind : CXTypeKind
    data : StaticArray(Void*, 2)
  end
  fun clang_getCursorType(CXCursor) : CXType
  fun clang_getTypeSpelling(CXType) : CXString
  fun clang_getTypedefDeclUnderlyingType(CXCursor) : CXType
  fun clang_getEnumDeclIntegerType(CXCursor) : CXType
  fun clang_getEnumConstantDeclValue(CXCursor) : LongLong
  fun clang_getEnumConstantDeclUnsignedValue(CXCursor) : ULongLong
  fun clang_getFieldDeclBitWidth(CXCursor) : Int
  fun clang_Cursor_getNumArguments(CXCursor) : Int
  fun clang_Cursor_getArgument(CXCursor, UInt) : CXCursor
  enum CXTemplateArgumentKind : UInt
    Null = 0
    Type = 1
    Declaration = 2
    NullPtr = 3
    Integral = 4
    Template = 5
    TemplateExpansion = 6
    Expression = 7
    Pack = 8
    Invalid = 9
  end
  fun clang_Cursor_getNumTemplateArguments(CXCursor) : Int
  fun clang_Cursor_getTemplateArgumentKind(CXCursor, UInt) : CXTemplateArgumentKind
  fun clang_Cursor_getTemplateArgumentType(CXCursor, UInt) : CXType
  fun clang_Cursor_getTemplateArgumentValue(CXCursor, UInt) : LongLong
  fun clang_Cursor_getTemplateArgumentUnsignedValue(CXCursor, UInt) : ULongLong
  fun clang_equalTypes(CXType, CXType) : UInt
  fun clang_getCanonicalType(CXType) : CXType
  fun clang_isConstQualifiedType(CXType) : UInt
  fun clang_Cursor_isMacroFunctionLike(CXCursor) : UInt
  fun clang_Cursor_isMacroBuiltin(CXCursor) : UInt
  fun clang_Cursor_isFunctionInlined(CXCursor) : UInt
  fun clang_isVolatileQualifiedType(CXType) : UInt
  fun clang_isRestrictQualifiedType(CXType) : UInt
  fun clang_getAddressSpace(CXType) : UInt
  fun clang_getTypedefName(CXType) : CXString
  fun clang_getPointeeType(CXType) : CXType
  fun clang_getTypeDeclaration(CXType) : CXCursor
  fun clang_getDeclObjCTypeEncoding(CXCursor) : CXString
  fun clang_Type_getObjCEncoding(CXType) : CXString
  fun clang_getTypeKindSpelling(CXTypeKind) : CXString
  fun clang_getFunctionTypeCallingConv(CXType) : CXCallingConv
  fun clang_getResultType(CXType) : CXType
  fun clang_getExceptionSpecificationType(CXType) : Int
  fun clang_getNumArgTypes(CXType) : Int
  fun clang_getArgType(CXType, UInt) : CXType
  fun clang_Type_getObjCObjectBaseType(CXType) : CXType
  fun clang_Type_getNumObjCProtocolRefs(CXType) : UInt
  fun clang_Type_getObjCProtocolDecl(CXType, UInt) : CXCursor
  fun clang_Type_getNumObjCTypeArgs(CXType) : UInt
  fun clang_Type_getObjCTypeArg(CXType, UInt) : CXType
  fun clang_isFunctionTypeVariadic(CXType) : UInt
  fun clang_getCursorResultType(CXCursor) : CXType
  fun clang_getCursorExceptionSpecificationType(CXCursor) : Int
  fun clang_isPODType(CXType) : UInt
  fun clang_getElementType(CXType) : CXType
  fun clang_getNumElements(CXType) : LongLong
  fun clang_getArrayElementType(CXType) : CXType
  fun clang_getArraySize(CXType) : LongLong
  fun clang_Type_getNamedType(CXType) : CXType
  fun clang_Type_isTransparentTagTypedef(CXType) : UInt
  enum CXTypeNullabilityKind : UInt
    NonNull = 0
    Nullable = 1
    Unspecified = 2
    Invalid = 3
  end
  fun clang_Type_getNullability(CXType) : CXTypeNullabilityKind
  enum CXTypeLayoutError : Int
    Invalid = -1
    Incomplete = -2
    Dependent = -3
    NotConstantSize = -4
    InvalidFieldName = -5
  end
  fun clang_Type_getAlignOf(CXType) : LongLong
  fun clang_Type_getClassType(CXType) : CXType
  fun clang_Type_getSizeOf(CXType) : LongLong
  fun clang_Type_getOffsetOf(CXType, Char*) : LongLong
  fun clang_Type_getModifiedType(CXType) : CXType
  fun clang_Cursor_getOffsetOfField(CXCursor) : LongLong
  fun clang_Cursor_isAnonymous(CXCursor) : UInt
  enum CXRefQualifierKind : UInt
    None = 0
    LValue = 1
    RValue = 2
  end
  fun clang_Type_getNumTemplateArguments(CXType) : Int
  fun clang_Type_getTemplateArgumentAsType(CXType, UInt) : CXType
  fun clang_Type_getCXXRefQualifier(CXType) : CXRefQualifierKind
  fun clang_Cursor_isBitField(CXCursor) : UInt
  fun clang_isVirtualBase(CXCursor) : UInt
  enum CX_CXXAccessSpecifier : UInt
    InvalidAccessSpecifier = 0
    Public = 1
    Protected = 2
    Private = 3
  end
  fun clang_getCXXAccessSpecifier(CXCursor) : CX_CXXAccessSpecifier
  enum CX_StorageClass : UInt
    Invalid = 0
    None = 1
    Extern = 2
    Static = 3
    PrivateExtern = 4
    OpenCLWorkGroupLocal = 5
    Auto = 6
    Register = 7
  end
  fun clang_Cursor_getStorageClass(CXCursor) : CX_StorageClass
  fun clang_getNumOverloadedDecls(CXCursor) : UInt
  fun clang_getOverloadedDecl(CXCursor, UInt) : CXCursor
  fun clang_getIBOutletCollectionType(CXCursor) : CXType
  enum CXChildVisitResult : UInt
    Break = 0
    Continue = 1
    Recurse = 2
  end
  alias CXCursorVisitor = (CXCursor, CXCursor, CXClientData) -> CXChildVisitResult
  fun clang_visitChildren(CXCursor, CXCursorVisitor, CXClientData) : UInt
  fun clang_getCursorUSR(CXCursor) : CXString
  fun clang_constructUSR_ObjCClass(Char*) : CXString
  fun clang_constructUSR_ObjCCategory(Char*, Char*) : CXString
  fun clang_constructUSR_ObjCProtocol(Char*) : CXString
  fun clang_constructUSR_ObjCIvar(Char*, CXString) : CXString
  fun clang_constructUSR_ObjCMethod(Char*, UInt, CXString) : CXString
  fun clang_constructUSR_ObjCProperty(Char*, CXString) : CXString
  fun clang_getCursorSpelling(CXCursor) : CXString
  fun clang_Cursor_getSpellingNameRange(CXCursor, UInt, UInt) : CXSourceRange
  alias CXPrintingPolicy = Void*
  enum CXPrintingPolicyProperty : UInt
    Indentation = 0
    SuppressSpecifiers = 1
    SuppressTagKeyword = 2
    IncludeTagDefinition = 3
    SuppressScope = 4
    SuppressUnwrittenScope = 5
    SuppressInitializers = 6
    ConstantArraySizeAsWritten = 7
    AnonymousTagLocations = 8
    SuppressStrongLifetime = 9
    SuppressLifetimeQualifiers = 10
    SuppressTemplateArgsInCXXConstructors = 11
    Bool = 12
    Restrict = 13
    Alignof = 14
    UnderscoreAlignof = 15
    UseVoidForZeroParams = 16
    TerseOutput = 17
    PolishForDeclaration = 18
    Half = 19
    MSWChar = 20
    IncludeNewlines = 21
    MSVCFormatting = 22
    ConstantsAsWritten = 23
    SuppressImplicitBase = 24
    FullyQualifiedName = 25
    LastProperty = 25
  end
  fun clang_PrintingPolicy_getProperty(CXPrintingPolicy, CXPrintingPolicyProperty) : UInt
  fun clang_PrintingPolicy_setProperty(CXPrintingPolicy, CXPrintingPolicyProperty, UInt) : Void
  fun clang_getCursorPrintingPolicy(CXCursor) : CXPrintingPolicy
  fun clang_PrintingPolicy_dispose(CXPrintingPolicy) : Void
  fun clang_getCursorPrettyPrinted(CXCursor, CXPrintingPolicy) : CXString
  fun clang_getCursorDisplayName(CXCursor) : CXString
  fun clang_getCursorReferenced(CXCursor) : CXCursor
  fun clang_getCursorDefinition(CXCursor) : CXCursor
  fun clang_isCursorDefinition(CXCursor) : UInt
  fun clang_getCanonicalCursor(CXCursor) : CXCursor
  fun clang_Cursor_getObjCSelectorIndex(CXCursor) : Int
  fun clang_Cursor_isDynamicCall(CXCursor) : Int
  fun clang_Cursor_getReceiverType(CXCursor) : CXType
  enum CXObjCPropertyAttrKind : UInt
    Noattr = 0
    Readonly = 1
    Getter = 2
    Assign = 4
    Readwrite = 8
    Retain = 16
    Copy = 32
    Nonatomic = 64
    Setter = 128
    Atomic = 256
    Weak = 512
    Strong = 1024
    UnsafeUnretained = 2048
    Class = 4096
  end
  fun clang_Cursor_getObjCPropertyAttributes(CXCursor, UInt) : UInt
  fun clang_Cursor_getObjCPropertyGetterName(CXCursor) : CXString
  fun clang_Cursor_getObjCPropertySetterName(CXCursor) : CXString
  enum CXObjCDeclQualifierKind : UInt
    None = 0
    In = 1
    Inout = 2
    Out = 4
    Bycopy = 8
    Byref = 16
    Oneway = 32
  end
  fun clang_Cursor_getObjCDeclQualifiers(CXCursor) : UInt
  fun clang_Cursor_isObjCOptional(CXCursor) : UInt
  fun clang_Cursor_isVariadic(CXCursor) : UInt
  fun clang_Cursor_isExternalSymbol(CXCursor, CXString*, CXString*, UInt*) : UInt
  fun clang_Cursor_getCommentRange(CXCursor) : CXSourceRange
  fun clang_Cursor_getRawCommentText(CXCursor) : CXString
  fun clang_Cursor_getBriefCommentText(CXCursor) : CXString
  fun clang_Cursor_getMangling(CXCursor) : CXString
  fun clang_Cursor_getCXXManglings(CXCursor) : CXStringSet*
  fun clang_Cursor_getObjCManglings(CXCursor) : CXStringSet*
  alias CXModule = Void*
  fun clang_Cursor_getModule(CXCursor) : CXModule
  fun clang_getModuleForFile(CXTranslationUnit, CXFile) : CXModule
  fun clang_Module_getASTFile(CXModule) : CXFile
  fun clang_Module_getParent(CXModule) : CXModule
  fun clang_Module_getName(CXModule) : CXString
  fun clang_Module_getFullName(CXModule) : CXString
  fun clang_Module_isSystem(CXModule) : Int
  fun clang_Module_getNumTopLevelHeaders(CXTranslationUnit, CXModule) : UInt
  fun clang_Module_getTopLevelHeader(CXTranslationUnit, CXModule, UInt) : CXFile
  fun clang_CXXConstructor_isConvertingConstructor(CXCursor) : UInt
  fun clang_CXXConstructor_isCopyConstructor(CXCursor) : UInt
  fun clang_CXXConstructor_isDefaultConstructor(CXCursor) : UInt
  fun clang_CXXConstructor_isMoveConstructor(CXCursor) : UInt
  fun clang_CXXField_isMutable(CXCursor) : UInt
  fun clang_CXXMethod_isDefaulted(CXCursor) : UInt
  fun clang_CXXMethod_isPureVirtual(CXCursor) : UInt
  fun clang_CXXMethod_isStatic(CXCursor) : UInt
  fun clang_CXXMethod_isVirtual(CXCursor) : UInt
  fun clang_CXXRecord_isAbstract(CXCursor) : UInt
  fun clang_EnumDecl_isScoped(CXCursor) : UInt
  fun clang_CXXMethod_isConst(CXCursor) : UInt
  fun clang_getTemplateCursorKind(CXCursor) : CXCursorKind
  fun clang_getSpecializedCursorTemplate(CXCursor) : CXCursor
  fun clang_getCursorReferenceNameRange(CXCursor, UInt, UInt) : CXSourceRange
  enum CXNameRefFlags : UInt
    Qualifier = 1
    TemplateArgs = 2
    SinglePiece = 4
  end
  enum CXTokenKind : UInt
    Punctuation = 0
    Keyword = 1
    Identifier = 2
    Literal = 3
    Comment = 4
  end
  struct CXToken
    int_data : StaticArray(UInt, 4)
    ptr_data : Void*
  end
  fun clang_getToken(CXTranslationUnit, CXSourceLocation) : CXToken*
  fun clang_getTokenKind(CXToken) : CXTokenKind
  fun clang_getTokenSpelling(CXTranslationUnit, CXToken) : CXString
  fun clang_getTokenLocation(CXTranslationUnit, CXToken) : CXSourceLocation
  fun clang_getTokenExtent(CXTranslationUnit, CXToken) : CXSourceRange
  fun clang_tokenize(CXTranslationUnit, CXSourceRange, CXToken**, UInt*) : Void
  fun clang_annotateTokens(CXTranslationUnit, CXToken*, UInt, CXCursor*) : Void
  fun clang_disposeTokens(CXTranslationUnit, CXToken*, UInt) : Void
  fun clang_getCursorKindSpelling(CXCursorKind) : CXString
  fun clang_getDefinitionSpellingAndExtent(CXCursor, Char**, Char**, UInt*, UInt*, UInt*, UInt*) : Void
  fun clang_enableStackTraces() : Void
  fun clang_executeOnThread((Void*) -> Void*, Void*, UInt) : Void
  alias CXCompletionString = Void*
  struct CXCompletionResult
    cursor_kind : CXCursorKind
    completion_string : CXCompletionString
  end
  enum CXCompletionChunkKind : UInt
    Optional = 0
    TypedText = 1
    Text = 2
    Placeholder = 3
    Informative = 4
    CurrentParameter = 5
    LeftParen = 6
    RightParen = 7
    LeftBracket = 8
    RightBracket = 9
    LeftBrace = 10
    RightBrace = 11
    LeftAngle = 12
    RightAngle = 13
    Comma = 14
    ResultType = 15
    Colon = 16
    SemiColon = 17
    Equal = 18
    HorizontalSpace = 19
    VerticalSpace = 20
  end
  fun clang_getCompletionChunkKind(CXCompletionString, UInt) : CXCompletionChunkKind
  fun clang_getCompletionChunkText(CXCompletionString, UInt) : CXString
  fun clang_getCompletionChunkCompletionString(CXCompletionString, UInt) : CXCompletionString
  fun clang_getNumCompletionChunks(CXCompletionString) : UInt
  fun clang_getCompletionPriority(CXCompletionString) : UInt
  fun clang_getCompletionAvailability(CXCompletionString) : CXAvailabilityKind
  fun clang_getCompletionNumAnnotations(CXCompletionString) : UInt
  fun clang_getCompletionAnnotation(CXCompletionString, UInt) : CXString
  fun clang_getCompletionParent(CXCompletionString, CXCursorKind*) : CXString
  fun clang_getCompletionBriefComment(CXCompletionString) : CXString
  fun clang_getCursorCompletionString(CXCursor) : CXCompletionString
  struct CXCodeCompleteResults
    results : CXCompletionResult*
    num_results : UInt
  end
  fun clang_getCompletionNumFixIts(CXCodeCompleteResults*, UInt) : UInt
  fun clang_getCompletionFixIt(CXCodeCompleteResults*, UInt, UInt, CXSourceRange*) : CXString
  enum CXCodeComplete_Flags : UInt
    IncludeMacros = 1
    IncludeCodePatterns = 2
    IncludeBriefComments = 4
    SkipPreamble = 8
    IncludeCompletionsWithFixIts = 16
  end
  enum CXCompletionContext : UInt
    Unexposed = 0
    AnyType = 1
    AnyValue = 2
    ObjCObjectValue = 4
    ObjCSelectorValue = 8
    CXXClassTypeValue = 16
    DotMemberAccess = 32
    ArrowMemberAccess = 64
    ObjCPropertyAccess = 128
    EnumTag = 256
    UnionTag = 512
    StructTag = 1024
    ClassTag = 2048
    Namespace = 4096
    NestedNameSpecifier = 8192
    ObjCInterface = 16384
    ObjCProtocol = 32768
    ObjCCategory = 65536
    ObjCInstanceMessage = 131072
    ObjCClassMessage = 262144
    ObjCSelectorName = 524288
    MacroName = 1048576
    NaturalLanguage = 2097152
    IncludedFile = 4194304
    Unknown = 8388607
  end
  fun clang_defaultCodeCompleteOptions() : UInt
  fun clang_codeCompleteAt(CXTranslationUnit, Char*, UInt, UInt, CXUnsavedFile*, UInt, UInt) : CXCodeCompleteResults*
  fun clang_sortCodeCompletionResults(CXCompletionResult*, UInt) : Void
  fun clang_disposeCodeCompleteResults(CXCodeCompleteResults*) : Void
  fun clang_codeCompleteGetNumDiagnostics(CXCodeCompleteResults*) : UInt
  fun clang_codeCompleteGetDiagnostic(CXCodeCompleteResults*, UInt) : CXDiagnostic
  fun clang_codeCompleteGetContexts(CXCodeCompleteResults*) : ULongLong
  fun clang_codeCompleteGetContainerKind(CXCodeCompleteResults*, UInt*) : CXCursorKind
  fun clang_codeCompleteGetContainerUSR(CXCodeCompleteResults*) : CXString
  fun clang_codeCompleteGetObjCSelector(CXCodeCompleteResults*) : CXString
  fun clang_getClangVersion() : CXString
  fun clang_toggleCrashRecovery(UInt) : Void
  alias CXInclusionVisitor = (CXFile, CXSourceLocation*, UInt, CXClientData) -> Void
  fun clang_getInclusions(CXTranslationUnit, CXInclusionVisitor, CXClientData) : Void
  enum CXEvalResultKind : UInt
    Int = 1
    Float = 2
    ObjCStrLiteral = 3
    StrLiteral = 4
    CFStr = 5
    Other = 6
    UnExposed = 0
  end
  alias CXEvalResult = Void*
  fun clang_Cursor_Evaluate(CXCursor) : CXEvalResult
  fun clang_EvalResult_getKind(CXEvalResult) : CXEvalResultKind
  fun clang_EvalResult_getAsInt(CXEvalResult) : Int
  fun clang_EvalResult_getAsLongLong(CXEvalResult) : LongLong
  fun clang_EvalResult_isUnsignedInt(CXEvalResult) : UInt
  fun clang_EvalResult_getAsUnsigned(CXEvalResult) : ULongLong
  fun clang_EvalResult_getAsDouble(CXEvalResult) : Double
  fun clang_EvalResult_getAsStr(CXEvalResult) : Char*
  fun clang_EvalResult_dispose(CXEvalResult) : Void
  alias CXRemapping = Void*
  fun clang_getRemappings(Char*) : CXRemapping
  fun clang_getRemappingsFromFileList(Char**, UInt) : CXRemapping
  fun clang_remap_getNumFiles(CXRemapping) : UInt
  fun clang_remap_getFilenames(CXRemapping, UInt, CXString*, CXString*) : Void
  fun clang_remap_dispose(CXRemapping) : Void
  enum CXVisitorResult : UInt
    Break = 0
    Continue = 1
  end
  struct CXCursorAndRangeVisitor
    context : Void*
    visit : (Void*, CXCursor, CXSourceRange) -> CXVisitorResult*
  end
  enum CXResult : UInt
    Success = 0
    Invalid = 1
    VisitBreak = 2
  end
  fun clang_findReferencesInFile(CXCursor, CXFile, CXCursorAndRangeVisitor) : CXResult
  fun clang_findIncludesInFile(CXTranslationUnit, CXFile, CXCursorAndRangeVisitor) : CXResult
  alias CXIdxClientFile = Void*
  alias CXIdxClientEntity = Void*
  alias CXIdxClientContainer = Void*
  alias CXIdxClientASTFile = Void*
  struct CXIdxLoc
    ptr_data : StaticArray(Void*, 2)
    int_data : UInt
  end
  struct CXIdxIncludedFileInfo
    hash_loc : CXIdxLoc
    filename : Char*
    file : CXFile
    is_import : Int
    is_angled : Int
    is_module_import : Int
  end
  struct CXIdxImportedASTFileInfo
    file : CXFile
    module : CXModule
    loc : CXIdxLoc
    is_implicit : Int
  end
  enum CXIdxEntityKind : UInt
    Unexposed = 0
    Typedef = 1
    Function = 2
    Variable = 3
    Field = 4
    EnumConstant = 5
    ObjCClass = 6
    ObjCProtocol = 7
    ObjCCategory = 8
    ObjCInstanceMethod = 9
    ObjCClassMethod = 10
    ObjCProperty = 11
    ObjCIvar = 12
    Enum = 13
    Struct = 14
    Union = 15
    CXXClass = 16
    CXXNamespace = 17
    CXXNamespaceAlias = 18
    CXXStaticVariable = 19
    CXXStaticMethod = 20
    CXXInstanceMethod = 21
    CXXConstructor = 22
    CXXDestructor = 23
    CXXConversionFunction = 24
    CXXTypeAlias = 25
    CXXInterface = 26
  end
  enum CXIdxEntityLanguage : UInt
    None = 0
    C = 1
    ObjC = 2
    CXX = 3
    Swift = 4
  end
  enum CXIdxEntityCXXTemplateKind : UInt
    NonTemplate = 0
    Template = 1
    TemplatePartialSpecialization = 2
    TemplateSpecialization = 3
  end
  enum CXIdxAttrKind : UInt
    Unexposed = 0
    IBAction = 1
    IBOutlet = 2
    IBOutletCollection = 3
  end
  struct CXIdxAttrInfo
    kind : CXIdxAttrKind
    cursor : CXCursor
    loc : CXIdxLoc
  end
  struct CXIdxEntityInfo
    kind : CXIdxEntityKind
    template_kind : CXIdxEntityCXXTemplateKind
    lang : CXIdxEntityLanguage
    name : Char*
    usr : Char*
    cursor : CXCursor
    attributes : CXIdxAttrInfo**
    num_attributes : UInt
  end
  struct CXIdxContainerInfo
    cursor : CXCursor
  end
  struct CXIdxIBOutletCollectionAttrInfo
    attr_info : CXIdxAttrInfo*
    objc_class : CXIdxEntityInfo*
    class_cursor : CXCursor
    class_loc : CXIdxLoc
  end
  enum CXIdxDeclInfoFlags : UInt
    CXIdxDeclFlag_Skipped = 1
  end
  struct CXIdxDeclInfo
    entity_info : CXIdxEntityInfo*
    cursor : CXCursor
    loc : CXIdxLoc
    semantic_container : CXIdxContainerInfo*
    lexical_container : CXIdxContainerInfo*
    is_redeclaration : Int
    is_definition : Int
    is_container : Int
    decl_as_container : CXIdxContainerInfo*
    is_implicit : Int
    attributes : CXIdxAttrInfo**
    num_attributes : UInt
    flags : UInt
  end
  enum CXIdxObjCContainerKind : UInt
    ForwardRef = 0
    Interface = 1
    Implementation = 2
  end
  struct CXIdxObjCContainerDeclInfo
    decl_info : CXIdxDeclInfo*
    kind : CXIdxObjCContainerKind
  end
  struct CXIdxBaseClassInfo
    base : CXIdxEntityInfo*
    cursor : CXCursor
    loc : CXIdxLoc
  end
  struct CXIdxObjCProtocolRefInfo
    protocol : CXIdxEntityInfo*
    cursor : CXCursor
    loc : CXIdxLoc
  end
  struct CXIdxObjCProtocolRefListInfo
    protocols : CXIdxObjCProtocolRefInfo**
    num_protocols : UInt
  end
  struct CXIdxObjCInterfaceDeclInfo
    container_info : CXIdxObjCContainerDeclInfo*
    super_info : CXIdxBaseClassInfo*
    protocols : CXIdxObjCProtocolRefListInfo*
  end
  struct CXIdxObjCCategoryDeclInfo
    container_info : CXIdxObjCContainerDeclInfo*
    objc_class : CXIdxEntityInfo*
    class_cursor : CXCursor
    class_loc : CXIdxLoc
    protocols : CXIdxObjCProtocolRefListInfo*
  end
  struct CXIdxObjCPropertyDeclInfo
    decl_info : CXIdxDeclInfo*
    getter : CXIdxEntityInfo*
    setter : CXIdxEntityInfo*
  end
  struct CXIdxCXXClassDeclInfo
    decl_info : CXIdxDeclInfo*
    bases : CXIdxBaseClassInfo**
    num_bases : UInt
  end
  enum CXIdxEntityRefKind : UInt
    Direct = 1
    Implicit = 2
  end
  enum CXSymbolRole : UInt
    None = 0
    Declaration = 1
    Definition = 2
    Reference = 4
    Read = 8
    Write = 16
    Call = 32
    Dynamic = 64
    AddressOf = 128
    Implicit = 256
  end
  struct CXIdxEntityRefInfo
    kind : CXIdxEntityRefKind
    cursor : CXCursor
    loc : CXIdxLoc
    referenced_entity : CXIdxEntityInfo*
    parent_entity : CXIdxEntityInfo*
    container : CXIdxContainerInfo*
    role : CXSymbolRole
  end
  struct IndexerCallbacks
    abort_query : (CXClientData, Void*) -> Int*
    diagnostic : (CXClientData, CXDiagnosticSet, Void*) -> Void*
    entered_main_file : (CXClientData, CXFile, Void*) -> CXIdxClientFile*
    pp_included_file : (CXClientData, CXIdxIncludedFileInfo*) -> CXIdxClientFile*
    imported_ast_file : (CXClientData, CXIdxImportedASTFileInfo*) -> CXIdxClientASTFile*
    started_translation_unit : (CXClientData, Void*) -> CXIdxClientContainer*
    index_declaration : (CXClientData, CXIdxDeclInfo*) -> Void*
    index_entity_reference : (CXClientData, CXIdxEntityRefInfo*) -> Void*
  end
  fun clang_index_isEntityObjCContainerKind(CXIdxEntityKind) : Int
  fun clang_index_getObjCContainerDeclInfo(CXIdxDeclInfo*) : CXIdxObjCContainerDeclInfo*
  fun clang_index_getObjCInterfaceDeclInfo(CXIdxDeclInfo*) : CXIdxObjCInterfaceDeclInfo*
  fun clang_index_getObjCCategoryDeclInfo(CXIdxDeclInfo*) : CXIdxObjCCategoryDeclInfo*
  fun clang_index_getObjCProtocolRefListInfo(CXIdxDeclInfo*) : CXIdxObjCProtocolRefListInfo*
  fun clang_index_getObjCPropertyDeclInfo(CXIdxDeclInfo*) : CXIdxObjCPropertyDeclInfo*
  fun clang_index_getIBOutletCollectionAttrInfo(CXIdxAttrInfo*) : CXIdxIBOutletCollectionAttrInfo*
  fun clang_index_getCXXClassDeclInfo(CXIdxDeclInfo*) : CXIdxCXXClassDeclInfo*
  fun clang_index_getClientContainer(CXIdxContainerInfo*) : CXIdxClientContainer
  fun clang_index_setClientContainer(CXIdxContainerInfo*, CXIdxClientContainer) : Void
  fun clang_index_getClientEntity(CXIdxEntityInfo*) : CXIdxClientEntity
  fun clang_index_setClientEntity(CXIdxEntityInfo*, CXIdxClientEntity) : Void
  alias CXIndexAction = Void*
  fun clang_IndexAction_create(CXIndex) : CXIndexAction
  fun clang_IndexAction_dispose(CXIndexAction) : Void
  enum CXIndexOptFlags : UInt
    None = 0
    SuppressRedundantRefs = 1
    IndexFunctionLocalSymbols = 2
    IndexImplicitTemplateInstantiations = 4
    SuppressWarnings = 8
    SkipParsedBodiesInSession = 16
  end
  fun clang_indexSourceFile(CXIndexAction, CXClientData, IndexerCallbacks*, UInt, UInt, Char*, Char**, Int, CXUnsavedFile*, UInt, CXTranslationUnit*, UInt) : Int
  fun clang_indexSourceFileFullArgv(CXIndexAction, CXClientData, IndexerCallbacks*, UInt, UInt, Char*, Char**, Int, CXUnsavedFile*, UInt, CXTranslationUnit*, UInt) : Int
  fun clang_indexTranslationUnit(CXIndexAction, CXClientData, IndexerCallbacks*, UInt, UInt, CXTranslationUnit) : Int
  fun clang_indexLoc_getFileLocation(CXIdxLoc, CXIdxClientFile*, CXFile*, UInt*, UInt*, UInt*) : Void
  fun clang_indexLoc_getCXSourceLocation(CXIdxLoc) : CXSourceLocation
  alias CXFieldVisitor = (CXCursor, CXClientData) -> CXVisitorResult
  fun clang_Type_visitFields(CXType, CXFieldVisitor, CXClientData) : UInt
end
