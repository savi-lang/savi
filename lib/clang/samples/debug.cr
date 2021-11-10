# This sample parses a C header file, and prints all Clang cursors to STDOUT.

require "../src/clang"

def visit(parent, deep = 0)
  parent.visit_children do |cursor|
    if deep == 0
      unless cursor.kind.macro_definition? ||
          cursor.kind.macro_expansion? ||
          cursor.kind.inclusion_directive?
        puts
      end
    else
      print " " * deep
    end

    puts "#{cursor.kind}: spelling=#{cursor.spelling} type.kind=#{cursor.type.kind} type.spelling=#{cursor.type.spelling.inspect} at #{cursor.location}"

    case cursor.kind
    when .class_decl?
      puts [:class, cursor.type.size_of].inspect
    when .field_decl?
      puts [:field, cursor.offset_of_field].inspect
    when .function_decl?
      puts [:function, cursor.mangling].inspect
    when .constructor?
      puts [:constructor, cursor.cxx_manglings].inspect
    when .destructor?
      puts [:destructor, cursor.cxx_manglings].inspect
    #when .cxx_method?
    #  puts [:cxx_method, cursor.spelling].inspect
    when .cxx_access_specifier?
      puts [:cxx_access_specifier, cursor.cxx_access_specifier].inspect
    end

    visit(cursor, deep + 2)

    Clang::ChildVisitResult::Continue
  end
end

index = Clang::Index.new

file_name = ARGV[0]? || "clang-c/Documentation.h"
args = [
  "-I/usr/include",
  "-I/usr/lib/llvm-5.0/lib/clang/5.0.0/include",
  "-I/usr/lib/llvm-5.0/include",
]
options = Clang::TranslationUnit.default_options |
  Clang::TranslationUnit::Options::DetailedPreprocessingRecord |
  Clang::TranslationUnit::Options::SkipFunctionBodies

case File.extname(file_name)
when ".h"
  files = [Clang::UnsavedFile.new("input.c", "#include <#{file_name}>\n")]
  tu = Clang::TranslationUnit.from_source(index, files, args, options)
when ".hpp"
  files = [Clang::UnsavedFile.new("input.cpp", "#include <#{file_name}>\n")]
  tu = Clang::TranslationUnit.from_source(index, files, args, options)
else
  #tu = Clang::TranslationUnit.from_source_file(index, file_name, args)
  files = [Clang::UnsavedFile.new(file_name, File.read(file_name))]
  tu = Clang::TranslationUnit.from_source(index, files, args, options)
end

visit(tu.cursor)
