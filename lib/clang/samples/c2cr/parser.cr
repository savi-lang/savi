require "../../src/clang"
require "./constant"
require "./type"

module C2CR
  class Parser
    protected getter index : Clang::Index
    protected getter translation_unit : Clang::TranslationUnit

    @remove_enum_prefix : String | Bool
    @remove_enum_suffix : String | Bool

    enum Process
      EVERYTHING
      FILE
    end

    def self.parse(header_name, args = [] of String, process : Process = Process::FILE)
      parser = new(header_name, args)
      parser.parse
      parser
    end

    def initialize(@header_name : String, args = [] of String,
                   @process : Process = Process::FILE,
                   @remove_enum_prefix = false,
                   @remove_enum_suffix = false)
      # TODO: support C++ (rename input.c to input.cpp)
      # TODO: support local filename (use quotes instead of angle brackets)
      files = [
        Clang::UnsavedFile.new("input.c", "#include <#{@header_name}>\n")
      ]
      options = Clang::TranslationUnit.default_options |
        Clang::TranslationUnit::Options.flags(DetailedPreprocessingRecord, SkipFunctionBodies)

      @index = Clang::Index.new
      @translation_unit = Clang::TranslationUnit.from_source(index, files, args, options)
    end

    def parse
      translation_unit.cursor.visit_children do |cursor|
        if @process.everything? || cursor.location.file_name.try(&.ends_with?("/#{@header_name}"))
          case cursor.kind
          when .macro_definition? then visit_define(cursor, translation_unit)
          when .typedef_decl?     then visit_typedef(cursor)
          when .enum_decl?        then visit_enum(cursor) unless cursor.spelling.empty?
          when .struct_decl?      then visit_struct(cursor) unless cursor.spelling.empty?
          when .union_decl?       then visit_union(cursor)
          when .function_decl?    then visit_function(cursor)
          when .var_decl?         then visit_var(cursor)
          #when .class_decl?
            # TODO: C++ classes
          #when .namespace_decl?
            # TODO: C++ namespaces
          when .macro_expansion?, .macro_instantiation?, .inclusion_directive?
            # skip
          else
            STDERR.puts "WARNING: unexpected #{cursor.kind} child cursor"
          end
        end
        Clang::ChildVisitResult::Continue
      end
    end

    def visit_define(cursor, translation_unit)
      # TODO: analyze the tokens to build the constant value (e.g. type cast, ...)
      # TODO: parse the result String to verify it is valid Crystal

      original = String.build do |str|
        previous = nil
        translation_unit.tokenize(cursor.extent, skip: 1) do |token|
          case token.kind
          when .comment?
            next
          when .punctuation?
            break if token.spelling == "#"
          when .literal?
            parse_literal_token(token.spelling, str)
            previous = token
            next
          else
            str << ' ' if previous
          end
          str << token.spelling
          previous = token
        end
      end

      if original.starts_with?('(') && original.ends_with?(')')
        value = original[1..-2]
      else
        value = original
      end

      if valid_crystal_literal?(value)
        puts "  #{cursor.spelling} = #{value}"
      else
        puts "  # #{cursor.spelling} = #{original.gsub('\n', "\r#  ")}"
      end
    end

    private def valid_crystal_literal?(value)
      case value
      when /^[-+]?(UInt|Long|ULong|LongLong|ULongLong)\.new\([+-]?[e0-9a-fA-F]+\)$/
        true
      when /^0x[e0-9a-fA-F]+$/
        true
      when /^[+-]?[e0-9a-fA-F]+$/
        true
      when /^[_A-Z][_A-Za-z0-9]+$/
        true
      else
        false
      end
    end

    private def parse_literal_token(literal, io)
      if literal =~ /^((0[X])?([+\-0-9A-F.e]+))(F|L|U|UL|LL|ULL)?$/i
        number, prefix, digits, suffix = $1, $2?, $3, $4?

        if prefix == "0x" && suffix == "F" && digits.size.odd?
          # false-positive: matched 0xFF, 0xffff, ...
          io << literal
        else
          case suffix.try(&.upcase)
          when "U"
            io << "UInt.new(" << number << ")"
          when "L"
            if number.index('.')
              io << "LongDouble.new(" << number << ")"
            else
              io << "Long.new(" << number << ")"
            end
          when "F"   then io << number << "_f32"
          when "UL"  then io << "ULong.new(" << number << ")"
          when "LL"  then io << "LongLong.new(" << number << ")"
          when "ULL" then io << "ULongLong.new(" << number << ")"
          else            io << number
          end
        end
      else
        io << literal
      end
    end

    def visit_typedef(cursor)
      children = [] of Clang::Cursor

      cursor.visit_children do |c|
        children << c
        Clang::ChildVisitResult::Continue
      end

      if children.size <= 1
        type = cursor.typedef_decl_underlying_type

        if type.kind.elaborated?
          t = type.named_type
          c = t.cursor

          # did the typedef named the anonymous struct? in which case we do
          # process the struct now, or did the struct already have a name? in
          # which case we already processed it:
          return unless c.spelling.empty?

          case t.kind
          when .record?
            case c.kind
            when .struct_decl?
              visit_struct(c, cursor.spelling)
            when .union_decl?
              visit_union(c, cursor.spelling)
            else
              STDERR.puts "WARNING: unexpected #{c.kind} for #{t.kind} within #{cursor.kind} (visit_typedef)"
            end
          when .enum?
            visit_enum(c, cursor.spelling)
          else
            STDERR.puts "WARNING: unexpected #{t.kind} within #{cursor.kind} (visit_typedef)"
          end
        else
          name = Constant.to_crystal(cursor.spelling)
          puts "  alias #{name} = #{Type.to_crystal(type)}"
        end
      else
        visit_typedef_proc(cursor, children)
      end
    end

    private def visit_typedef_type(cursor, c)
      name = Constant.to_crystal(cursor.spelling)
      type = Type.to_crystal(c.type.canonical_type)
      puts "  alias #{name} = #{type}"
    end

    private def visit_typedef_proc(cursor, children)
      if children.first.kind.parm_decl?
        ret = "Void"
      else
        ret = Type.to_crystal(children.shift.type.canonical_type)
      end

      print "  alias #{Constant.to_crystal(cursor.spelling)} = ("
      children.each_with_index do |c, index|
        print ", " unless index == 0
        #unless c.spelling.empty?
        #  print c.spelling.underscore
        #  print " : "
        #end
        print Type.to_crystal(c.type)
      end
      print ") -> "
      puts ret
    end

    def visit_enum(cursor, spelling = cursor.spelling)
      type = cursor.enum_decl_integer_type.canonical_type
      puts "  enum #{Constant.to_crystal(spelling)} : #{Type.to_crystal(type)}"

      values = [] of {String, Int64|UInt64}

      cursor.visit_children do |c|
        case c.kind
        when .enum_constant_decl?
          value = case type.kind
                  when .u_int? then c.enum_constant_decl_unsigned_value
                  else              c.enum_constant_decl_value
                  end
          values << {c.spelling, value}
        else
          STDERR.puts "WARNING: unexpected #{c.kind} within #{cursor.kind} (visit_enum)"
        end
        Clang::ChildVisitResult::Continue
      end

      prefix = cleanup_prefix_from_enum_constant(cursor, values)
      suffix = cleanup_suffix_from_enum_constant(cursor, values)

      values.each do |(name, value)|
        if name.includes?(spelling)
          # when the enum spelling is fully duplicated in constants: remove it all
          constant = name.sub(spelling, "")
          while constant.starts_with?('_')
            constant = constant[1..-1]
          end
        else
          # remove similar prefix/suffix patterns from all constants:
          start = prefix.size
          stop = Math.max(suffix.size + 1, 1)
          constant = name[start .. -stop]
        end

        unless constant[0].ascii_uppercase?
          constant = Constant.to_crystal(constant)
        end

        puts "    #{constant} = #{value}"
      end

      puts "  end"
    end

    private def cleanup_prefix_from_enum_constant(cursor, values)
      prefix = ""
      reference = values.size > 1 ? values.first[0] : cursor.spelling

      if pre = @remove_enum_prefix
        reference = pre if pre.is_a?(String)

        reference.each_char do |c|
          testing = prefix + c

          if values.all? { |e| e[0].starts_with?(testing) }
            prefix = testing
          else
            # TODO: try to match a word delimitation, to only remove whole words
            #       not a few letters that happen to match.
            return prefix
          end
        end
      end

      prefix
    end

    private def cleanup_suffix_from_enum_constant(cursor, values)
      suffix = ""
      reference = values.size > 1 ? values.first[0] : cursor.spelling

      if suf = @remove_enum_suffix
        reference = suf if suf.is_a?(String)

        reference.reverse.each_char do |c|
          testing = c.to_s + suffix

          if values.all? { |e| e[0].ends_with?(testing) }
            suffix = testing
          else
            # try to match a word delimitation, to only remove whole words not a
            # few letters that happen to match:
            a, b = suffix[0]?, suffix[1]?
            if a && b && (a == '_' || (a.ascii_uppercase? && !b.ascii_uppercase?))
              return suffix
            else
              return ""
            end
          end
        end
      end

      suffix
    end

    def visit_struct(cursor, spelling = cursor.spelling)
      members_count = 0

      definition = String.build do |str|
        str.puts "  struct #{Constant.to_crystal(spelling)}"

        cursor.visit_children do |c|
          members_count += 1

          case c.kind
          when .field_decl?
            str.puts "    #{c.spelling.underscore} : #{Type.to_crystal(c.type)}"
          when .struct_decl?
            if c.type.kind.record?
              # skip
            else
              STDERR.puts [:TODO, :inner_struct, c].inspect
            end
          else
            STDERR.puts "WARNING: unexpected #{c.kind} within #{cursor.kind} (visit_struct)"
          end
          Clang::ChildVisitResult::Continue
        end

        str.puts "  end"
      end

      if members_count == 0
        puts "  type #{Constant.to_crystal(spelling)} = Void"
      else
        puts definition
      end
    end

    def visit_union(cursor, spelling = cursor.spelling)
      # anonymous? already processed?
      return if spelling.empty?

      puts "  union #{Constant.to_crystal(spelling)}"

      cursor.visit_children do |c|
        case c.kind
        when .field_decl?
          puts "    #{c.spelling.underscore} : #{Type.to_crystal(c.type)}"
        else
          STDERR.puts "WARNING: unexpected #{c.kind} within #{cursor.kind} (visit_union)"
        end
        Clang::ChildVisitResult::Continue
      end

      puts "  end"
    end

    def visit_function(cursor)
      arguments = cursor.arguments

      print "  fun "
      print cursor.spelling
      print '('
      cursor.arguments.each_with_index do |c, index|
        print ", " unless index == 0
        print Type.to_crystal(c.type)  # .canonical_type
      end
      print ") : "
      puts Type.to_crystal(cursor.result_type)  # .canonical_type
    end

    def visit_var(cursor)
      type = Type.to_crystal(cursor.type.canonical_type)
      #    puts "  $#{cursor.spelling} : #{type}"
    end
  end
end
