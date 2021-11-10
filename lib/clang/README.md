# libclang bindings for Crystal

Usage:

```crystal
require "clang"

index = Clang::Index.new

files = [
  #Clang::UnsavedFile.new("input.c", "#include <pcre.h>\n"),
  Clang::UnsavedFile.new("input.c", "#include <clang/Basic/ABI.h>\n"),
]
tu = Clang::TranslationUnit.from_source(index, files, [
  "-I/usr/include",
  "-I/usr/lib/llvm-5.0/include",
])

tu.cursor.visit_children do |cursor|
  p cursor

  Clang::ChildVisitResult::Continue
end
```

## Samples

See the `samples` folder for some example usages:

- `samples/debug.cr` will print the AST of C or C++ headers as they are parsed;
- `samples/c2cr.cr` will automatically generate Crystal bindings for a C header.

For example:

```sh
$ shards build --release

$ bin/c2cr -I/usr/lib/llvm-5.0/include llvm-c/Core.h \
    --remove-enum-prefix=LLVM --remove-enum-suffix > llvm-c/Core.cr

$ bin/c2cr -I/usr/lib/llvm-5.0/include clang-c/Index.h \
    --remove-enum-prefix > clang-c/Index.cr

$ bin/c2cr gtk-2.0/gtk/gtkenums.h --remove-enum-prefix > gtk/enums.cr
```

## Reference

- [C interface to Clang](http://clang.llvm.org/doxygen/group__CINDEX.html)

## License

Distributed under the Apache 2.0 license.
