struct LLVM::Function
  def add_attribute(
    attribute : Attribute,
    index = AttributeIndex::FunctionIndex,
    value = 0_u64
  )
    return if attribute.value == 0
    {% if LibLLVM.has_constant?(:AttributeRef) %}
      context = LibLLVM.get_module_context(LibLLVM.get_global_parent(self))
      attribute.each_kind do |kind|
        attribute_ref = LibLLVM.create_enum_attribute(context, kind, value)
        LibLLVM.add_attribute_at_index(self, index, attribute_ref)
      end
    {% else %}
      case index
      when AttributeIndex::FunctionIndex
        LibLLVM.add_function_attr(self, attribute)
      when AttributeIndex::ReturnIndex
        raise "Unsupported: can't set attributes on function return type in LLVM < 3.9"
      else
        LibLLVM.add_attribute(params[index.to_i - 1], attribute)
      end
    {% end %}
  end
end
