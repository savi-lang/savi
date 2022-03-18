require "clang"

class Savi::FFIGen
  @header_name : String

  def initialize(@header_name)
    @savi_name = "_FFI" # TODO: Configurable
    @need_struct_decls = [] of String

    base_name = File.basename(@header_name)
    dir_name = File.dirname(@header_name)
    c_file = Clang::UnsavedFile.new("input.c", "#include <#{base_name}>\n")
    @clang_unit = Clang::TranslationUnit
      .from_source(Clang::Index.new, [c_file], ["-I#{dir_name}"])
  end

  def emit(io : IO)
    io.puts ":module #{@savi_name}"
    emit_function_decls(io)
  end

  private def emit_function_decls(io : IO)
    is_first_function_decl = true
    each_top_entity { |cursor|
      # Skip entities that aren't function declarations in the specified header.
      next unless cursor.kind.function_decl? \
        && cursor.location.file_name.try(&.==(@header_name))

      # Each function gets a blank line above it, except the first function.
      io.puts unless is_first_function_decl
      is_first_function_decl = false

      # Emit documentation comments, if any.
      comment_lines(cursor).try(&.each { |line|
        io.puts(line.empty? ? "  ::" : "  :: #{line}")
      })

      # Emit function name.
      # TODO: Handle optional variadic keyword here.
      io.print "  :ffi #{cursor.spelling}"

      # Emit function arguments.
      io.puts "(" unless cursor.arguments.empty?
      cursor.arguments.each_with_index { |arg, index|
        arg_name = arg.spelling
        arg_name = "arg#{index + 1}" if arg_name.empty?
        io.puts "    #{arg_name} #{type_for(arg.type)}"
      }
      io.print "  )" unless cursor.arguments.empty?

      # Emit function return type and finish the line.
      io.print " #{type_for(cursor.result_type)}" \
        unless cursor.result_type.kind.void?
      io.puts
    }
  end

  private def each_top_entity(&block : Clang::Cursor ->)
    @clang_unit.cursor.visit_children { |cursor|
      block.call(cursor)
      Clang::ChildVisitResult::Continue
    }
  end

  private def comment_lines(cursor : Clang::Cursor) : Array(String)?
    # Strip away C-style line comments and block comments and split lines.
    lines = cursor.raw_comment_text.try(
      &.sub(%r{\A[ \t]*/[\*/]+[ \t]*}m, "")
      .sub(%r{[ \t]*\*+/\s*\z}m, "")
      .split(%r{\n[ \t]*[\*/]*[ \t]*}m)
      .map(&.strip)
      .skip_while(&.empty?)
      .reverse
      .skip_while(&.empty?)
      .reverse
    )
  end

  private def type_for(t : Clang::Type) : String
    t = t.canonical_type
    canonical = t.canonical_type
    case canonical.kind
    # when .invalid?               then "TODO"
    # when .unexposed?             then "TODO"
    # when .void?                  then "TODO"
    when .bool?                  then "Bool"
    when .char_u?                then "U8"
    when .u_char?                then "U8"
    when .char16?                then "U16"
    when .char32?                then "U32"
    when .u_short?               then "U16"
    when .u_int?                 then "U32"
    when .u_long?                then "ULong"
    when .u_long_long?           then "U64"
    when .u_int128?              then "U128"
    when .char_s?                then "I8"
    when .s_char?                then "I8"
    # when .w_char?                then "TODO"
    when .short?                 then "I16"
    when .int?                   then "I32"
    when .long?                  then "ILong"
    when .long_long?             then "I64"
    when .int128?                then "I128"
    when .float?                 then "F32"
    when .double?                then "F64"
    # when .long_double?           then "TODO"
    # when .null_ptr?              then "TODO"
    # when .overload?              then "TODO"
    # when .dependent?             then "TODO"
    # when .obj_c_id?              then "TODO"
    # when .obj_c_class?           then "TODO"
    # when .obj_c_sel?             then "TODO"
    # when .float128?              then "TODO"
    # when .first_builtin?         then "TODO"
    # when .last_builtin?          then "TODO"
    # when .complex?               then "TODO"
    # when .pointer?               then "TODO"
    # when .block_pointer?         then "TODO"
    # when .l_value_reference?     then "TODO"
    # when .r_value_reference?     then "TODO"
    when .record?
      if (struct_name = canonical.spelling.split("struct ")[1]?)
        # If it's a struct, add it to the list of structs that need declaration.
        # We'll make sure we declare it in the later part of the Savi code.
        @need_struct_decls << struct_name
        "#{@savi_name}_#{struct_name}"
      else
        "UNKNOWN\n// #{t.inspect}\n"
      end
    # when .enum?                  then "TODO"
    # when .typedef?               then "TODO"
    # when .obj_c_interface?       then "TODO"
    # when .obj_c_object_pointer?  then "TODO"
    # when .function_no_proto?     then "TODO"
    # when .function_proto?        then "TODO"
    # when .constant_array?        then "TODO"
    # when .vector?                then "TODO"
    # when .incomplete_array?      then "TODO"
    # when .variable_array?        then "TODO"
    # when .dependent_sized_array? then "TODO"
    # when .member_pointer?        then "TODO"
    # when .auto?                  then "TODO"
    # when .elaborated?            then "TODO"
    when .pointer?
      case t.pointee_type.kind

      when .void?
        # Void pointer is C shorthand for "could be anything"...
        # We call that concept `CPointerAny` 'round these parts.
        "CPointerAny"

      when .char_s?, .s_char?
        # A C `char*` is almost always a sloppy stand-in for `unsigned char*`,
        # So we us
        "CPointer(U8)"

      else
        "CPointer(#{type_for(t.pointee_type)})"
      end
    else
      "UNKNOWN\n// #{t.inspect}\n"
    end
  end
end
