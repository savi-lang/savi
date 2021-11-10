module Clang
  # NOTE: since clang 7+
  class PrintingPolicy
    alias Property = LibC::CXPrintingPolicyProperty

    def initialize(@printing_policy = LibC::CXPrintingPolicy)
    end

    def finalize
      LibC.clang_PrintingPolicy_dispose(self)
    end

    def get_property(property : Property)
      LibC.clang_PrintingPolicy_getProperty(self, property)
    end

    def set_property(property : Property, value : UInt32)
      LibC.clang_PrintingPolicy_setProperty(self, property, value)
    end

    def to_unsafe
      @printing_policy
    end
  end
end
