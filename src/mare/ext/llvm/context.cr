class LLVM::Context
  def intptr(target_data : TargetData) : Type
    Type.new LibLLVM.intptr_type_in_context(self, target_data)
  end

  def opaque_struct(name : String) : Type
    Type.new LibLLVM.struct_create_named(self, name)
  end
  
  def const_inbounds_gep(value : Value, indices : Array(Value))
    Value.new LibLLVM.const_inbounds_gep(value, indices.to_unsafe.as(LibLLVM::ValueRef*), indices.size)
  end
  
  def const_bit_cast(value : Value, to_type : Type)
    Value.new LibLLVM.const_bit_cast(value, to_type)
  end
  
  # (derived from existing parse_ir method)
  def parse_bitcode(buf : MemoryBuffer)
    ret = LibLLVM.parse_bitcode_in_context(self, buf, out mod, out msg)
    if ret != 0 && msg
      raise LLVM.string_and_dispose(msg)
    end
    {% if LibLLVM::IS_38 %}
      Module.new(mod, "unknown", self)
    {% else %} # LLVM >= 3.9
      Module.new(mod, self)
    {% end %}
  end
end
