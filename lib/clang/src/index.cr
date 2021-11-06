module Clang
  class Index
    alias GlobalOptions = LibC::CXGlobalOptFlags

    # Creates a new Index.
    #
    # - *exclude_declarations_from_pch*: allow enumeration of "local"
    #   declarations (when loading any new translation units). A "local"
    #   declaration is one that belongs in the translation unit itself and not
    #   in a precompiled header that was used by the translation unit. If false,
    #   all declarations will be enumerated.
    def initialize(exclude_declarations_from_pch = false, display_diagnostics = true)
      @index = LibC.clang_createIndex(exclude_declarations_from_pch ? 1 : 0, display_diagnostics ? 1 : 0)
    end

    def finalize
      LibC.clang_disposeIndex(self)
    end

    def global_options
      LibC.clang_CXIndex_getGlobalOptions(self)
    end

    def global_options=(value : GlobalOptions)
      LibC.clang_CXIndex_setGlobalOptions(self, value)
      value
    end

    def set_invocation_emission_path_option(path : String)
      LibC.clang_CXIndex_setInvocationEmissionPathOption(self, path)
    end

    def to_unsafe
      @index
    end
  end
end
