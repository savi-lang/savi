---
pass: type_check
---

It allows type aliases to pass along type parameters:

```savi
:trait Sizeable
  :fun size USize

:class GenericClass(A, B Sizeable'read)

:alias GenericAlias(C, D String'read): GenericClass(C, D)
```
```savi
    a = GenericAlias(U64, String'ref).new ::type=> GenericClass(U64, String'ref)
```

---

It allows convenience type aliases to be used to imply type arguments:

```savi
:class GenericClassInNeedOfConvenience(A val, B val = String, C val = String)

:alias ConvenienceAlias: GenericClassInNeedOfConvenience(U64, U8)

:class UsesConvenienceAlias
  :let a ConvenienceAlias
  :new (@a)
```
```savi
    a = ConvenienceAlias.new ::type=> GenericClassInNeedOfConvenience(U64, U8, String)
    UsesConvenienceAlias.new(a)
```

---

It handles type-parameter-recursive type aliases:

```savi
:alias MyData: (String | U64 | Array(MyData)'val)
```
```savi
    data MyData = [
      "Hello"
      "World"
      99
      [
        "Wow"
        [1, 2, 3] ::type=> Array(MyData)'val
      ]           ::type=> Array(MyData)'val
    ]             ::type=> Array(MyData)'val
    data ::type=> (String | U64 | Array(MyData)'val)
```

---

It complains when a type alias is directly recursive:

```savi
:alias AdInfinitum: (String | U64 | AdInfinitum)
```
```savi
    data AdInfinitum = "Uh oh"
```
```error
This type alias is directly recursive, which is not supported:
:alias AdInfinitum: (String | U64 | AdInfinitum)
       ^~~~~~~~~~~

- only recursion via type arguments is supported in this expression:
:alias AdInfinitum: (String | U64 | AdInfinitum)
                    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~
```
