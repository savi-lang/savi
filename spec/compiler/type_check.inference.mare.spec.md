---
pass: type_check
---

It infers a local's type based on assignment:

```mare
    x = "Hello, World!"
    x ::type=> String
```

---

It infers a prop's type based on the prop initializer:

```mare
  :prop x: "Hello, World!"
  :fun test_x
    @x ::type=> String
```

---

It infers assignment from an allocated class:

```mare
:class SomeAllocatableClass
```
```mare
    x = SomeAllocatableClass.new ::type=> SomeAllocatableClass
    x                            ::type=> SomeAllocatableClass
    x_non = SomeAllocatableClass ::type=> SomeAllocatableClass'non
    x_non                        ::type=> SomeAllocatableClass'non
    nope SomeAllocatableClass = SomeAllocatableClass // not okay; right is a non
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    nope SomeAllocatableClass = SomeAllocatableClass // not okay; right is a non
                                ^~~~~~~~~~~~~~~~~~~~

- it is required here to be a subtype of SomeAllocatableClass:
    nope SomeAllocatableClass = SomeAllocatableClass // not okay; right is a non
         ^~~~~~~~~~~~~~~~~~~~

- but the type of the singleton value for this type was SomeAllocatableClass'non:
    nope SomeAllocatableClass = SomeAllocatableClass // not okay; right is a non
                                ^~~~~~~~~~~~~~~~~~~~
```

---

It infers return type from param type or another return type:

```mare
    @infer_from_call_return(42) ::type=> I32

  :fun non infer_from_param(n I32): n ::type=> I32
  :fun non infer_from_call_return(n I32): @infer_from_param(n) ::type=> I32
```

---

It infers param type from local assignment or from the return type:

```mare
    @infer_from_assign(42) ::type=> I32
    @infer_from_return_type(42) ::type=> I32

  :fun non infer_from_assign(n): m I32 = n ::type=> I32
  :fun non infer_from_return_type(n) I32: n ::type=> I32
```

---

It complains when unable to infer mutually recursive return types:

```mare
    @tweedle_dum(42)

  :fun non tweedle_dee(n I32): @tweedle_dum(n)
  :fun non tweedle_dum(n I32): @tweedle_dee(n)
```
```error
This return value needs an explicit type; it could not be inferred:
  :fun non tweedle_dum(n I32): @tweedle_dee(n)
                                ^~~~~~~~~~~
```

---

It infers a b-prefixed string literal as a Bytes object:

```mare
    b"example" ::type=> Bytes
```

---

It infers an integer literal based on an assignment:

```mare
    x (U64 | None) = 42 ::type=> U64
    x ::type=> (U64 | None)
```

---

It infers an integer literal based on a prop type:

```mare
  :prop x (U64 | None): 42
  :fun test_x
    @x ::type=> (U64 | None)
```

---

It infers an integer literal through an if statement:

```mare
    x (U64 | String | None) = if True (
      42 ::type=> U64
    )
    x ::type=> (U64 | String | None)
```

---

It infers an integer literal within the else body of an if statement:

```mare
    u = U64[99]
    x = if True (
      u
    |
      0 ::type=> U64
    ) ::type=> U64
```

---

It complains when a literal couldn't be resolved to a single type:

```mare
    x (F64 | U64) = 42
```
```error
This literal value couldn't be inferred as a single concrete type:
    x (F64 | U64) = 42
                    ^~

- it is required here to be a subtype of (F64 | U64):
    x (F64 | U64) = 42
      ^~~~~~~~~~~

- and the literal itself has an intrinsic type of Numeric:
    x (F64 | U64) = 42
                    ^~

- Please wrap an explicit numeric type around the literal (for example: U64[42])
```

---

It complains when literal couldn't resolve even when calling u64 method:

```mare
    x = 42.u64
```
```error
This literal value couldn't be inferred as a single concrete type:
    x = 42.u64
        ^~

- and the literal itself has an intrinsic type of Numeric:
    x = 42.u64
        ^~

- Please wrap an explicit numeric type around the literal (for example: U64[42])
```

---

It complains when literal couldn't resolve and had conflicting hints:

```mare
    string = "Hello, World"
    case (
    | string.size < 10 | U64[99]
    | string.size > 90 | I64[88]
    | 0
    )
```
```error
This literal value couldn't be inferred as a single concrete type:
    | 0
      ^

- it is suggested here that it might be a U64:
    | string.size < 10 | U64[99]
                            ^~~~

- it is suggested here that it might be a I64:
    | string.size > 90 | I64[88]
                            ^~~~

- and the literal itself has an intrinsic type of Numeric:
    | 0
      ^

- Please wrap an explicit numeric type around the literal (for example: U64[0])
```

---

It infers the type of an array literal from its elements:

```mare
    x = ["one", "two", "three"] ::type=> Array(String)
    x                           ::type=> Array(String)
```

---

It infers the element types of an array literal from an assignment:

```mare
    // TODO: allow syntax: Array(U64 | None)'val?
    x Array((U64 | None))'val = [
      1 ::type=> U64
      2 ::type=> U64
      3 ::type=> U64
    ] ::type=> Array((U64 | None))'val
    x ::type=> Array((U64 | None))'val
```

---

It complains when lifting the cap of an array with non-sendable elements:

```mare
    s String'ref = String.new
    array1 Array(String'ref)'val = [String.new_iso, String.new_iso] // okay
    array2 Array(String'ref)'val = [s, s] // not okay
```
```error
This array literal can't have a reference cap of val unless all of its elements are sendable:
    array2 Array(String'ref)'val = [s, s] // not okay
                                   ^~~~~~

- it is required here to be a subtype of Array(String'ref)'val:
    array2 Array(String'ref)'val = [s, s] // not okay
           ^~~~~~~~~~~~~~~~~~~~~
```

---

It infers an empty array literal from its antecedent:

TODO: type assertions in mare.spec.md files:
```mare
    x Array(U64) = [] ::type=> Array(U64)
    x                 ::type=> Array(U64)
    x << 99
```

---

It complains when an empty array literal has no antecedent:

```mare
    x = []
    x << 99
```
```error
The type of this empty array literal could not be inferred (it needs an explicit type):
    x = []
        ^~
```

---

It complains when trying to implicitly recover an array literal:

```mare
    x_ref String'ref = String.new
    array_ref ref = [x_ref] // okay
    array_box box = [x_ref] // okay
    array_val val = [x_ref] // not okay
```
TODO: This error message will change when we have array literal recovery.
```error
The type of this expression doesn't meet the constraints imposed on it:
    array_val val = [x_ref] // not okay
                    ^~~~~~~

- it is required here to be a subtype of val:
    array_val val = [x_ref] // not okay
              ^~~

- but the type of the array literal was Array(String'ref):
    array_val val = [x_ref] // not okay
                    ^~~~~~~
```

---

It infers prop setters to return the alias of the assigned value:

```mare
:class HasStringIso
  :prop string_iso String'iso: String.new_iso
```
```mare
    wrapper_iso = HasStringIso.new
    returned_2 String'tag = wrapper_iso.string_iso = String.new_iso // okay
    returned_3 String'iso = wrapper_iso.string_iso = String.new_iso // not okay
```
```error
The type of this expression doesn't meet the constraints imposed on it:
    returned_3 String'iso = wrapper_iso.string_iso = String.new_iso // not okay
    ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

- it is required here to be a subtype of String'iso:
    returned_3 String'iso = wrapper_iso.string_iso = String.new_iso // not okay
               ^~~~~~~~~~

- but the type of the return value was String'iso'aliased:
    returned_3 String'iso = wrapper_iso.string_iso = String.new_iso // not okay
                                        ^~~~~~~~~~
```
