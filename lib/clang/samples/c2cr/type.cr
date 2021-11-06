module C2CR
  module Type
    def self.to_crystal(type : Clang::Type)
      case type.kind
      when .void? then "Void"
      when .bool? then "Bool"
      when .char_u?, .u_char? then "Char"
      when .char16?, .u_short? then "Short"
      when .char32? then "UInt32"
      when .u_int? then "UInt"
      when .u_long? then "ULong"
      when .u_long_long? then "ULongLong"
      when .w_char? then "WChar"
      when .char_s?, .s_char? then "Char"
      when .short? then "Short"
      when .int? then "Int"
      when .long? then "Long"
      when .long_long? then "LongLong"
      when .float? then "Float"
      when .double? then "Double"
      when .long_double? then "LongDouble"
      when .pointer? then visit_pointer(type)
      when .enum?, .record?
        spelling = type.cursor.spelling
        spelling = type.spelling if type.cursor.spelling.empty?
        Constant.to_crystal(spelling)
      when .elaborated? then to_crystal(type.named_type)
      when .typedef?
        if (spelling = type.spelling).starts_with?('_')
          to_crystal(type.canonical_type)
        else
          Constant.to_crystal(spelling)
        end
      when .constant_array? then visit_constant_array(type)
      #when .vector? then visit_vector(type)
      when .incomplete_array? then visit_incomplete_array(type)
      #when .variable_array? then visit_variable_array(type)
      #when .dependent_sized_array? then visit_dependent_sized_array(type)
      when .function_proto? then visit_function_proto(type)
      when .function_no_proto? then visit_function_no_proto(type)
      when .unexposed? then to_crystal(type.canonical_type)
      else
        raise "unsupported C type: #{type}"
      end
    end

    def self.visit_pointer(type)
      #pointee = to_crystal(type.pointee_type.canonical_type)
      pointee = to_crystal(type.pointee_type)
      "#{pointee}*"
    end

    def self.visit_constant_array(type)
      #element = to_crystal(type.array_element_type.canonical_type)
      element = to_crystal(type.array_element_type)
      "StaticArray(#{element}, #{type.array_size})"
    end

    def self.visit_function_proto(type)
      String.build do |str|
        str << '('
        type.arguments.each_with_index do |t, index|
          str << ", " unless index == 0
          str << Type.to_crystal(t)
        end
        str << ") -> "
        str << Type.to_crystal(type.result_type)
      end
    end

    def self.visit_function_no_proto(type)
      STDERR.puts "# UNSUPPORTED: FunctionNoProto #{type.inspect}"
    end

    def self.visit_incomplete_array(type)
      #element_type = Type.to_crystal(type.array_element_type.canonical_type)
      element_type = Type.to_crystal(type.array_element_type)
      "#{element_type}*"
    end
  end
end
