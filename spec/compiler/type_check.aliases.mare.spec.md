---
pass: type_check
---

It allows type aliases to pass along type parameters:

```mare
:trait Sizeable
  :fun size USize

:class GenericClass(A, B Sizeable'read)

:alias GenericAlias(C, D String'read): GenericClass(C, D)
```
```mare
    a = GenericAlias(U64, String'ref).new ::type=> GenericClass(U64, String'ref)
```

---

It handles type-parameter-recursive type aliases:

```mare
:alias MyData: (String | U64 | Array(MyData)'val)
```
```mare
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

```mare
:alias AdInfinitum: (String | U64 | AdInfinitum)
```
```mare
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
