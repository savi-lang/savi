---
pass: t_type_check
---

It infers a local's type based on assignment:

```savi
    x = "Hello, World!"
    x ::t_type=> String
```

---

It infers a prop's type based on the prop initializer:

```savi
  :var x: "Hello, World!"
  :fun test_x
    @x ::t_type=> String
```

---

TODO: It infers assignment from an allocated class:

```savi
:class SomeAllocatableClass
```
```savi
    x = SomeAllocatableClass.new ::t_type=> SomeAllocatableClass
    x                            ::t_type=> SomeAllocatableClass
    x_non = SomeAllocatableClass ::t_type=> SomeAllocatableClass
    x_non                        ::t_type=> SomeAllocatableClass
    // nope SomeAllocatableClass = SomeAllocatableClass // not okay; right is a non
```

---

It infers return type from param type or another return type:

```savi
    @infer_from_call_return(42) ::t_type=> I32

  :fun non infer_from_param(n I32): n ::t_type=> I32
  :fun non infer_from_call_return(n I32): @infer_from_param(n) ::t_type=> I32
```

---

It infers param type from local assignment or from the return type:

```savi
    @infer_from_assign(42) ::t_type=> I32
    @infer_from_return_type(42) ::t_type=> I32

  :fun non infer_from_assign(n): m I32 = n ::t_type=> I32
  :fun non infer_from_return_type(n) I32: n ::t_type=> I32
```

---

It complains when unable to infer mutually recursive return types:

```savi
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

```savi
    b"example" ::t_type=> Bytes
```

---

It infers an integer literal based on an assignment:

```savi
    x (U64 | None) = 42 ::t_type=> U64
    x ::t_type=> (U64 | None)
```

---

It infers an integer literal based on a property type:

```savi
  :var x (U64 | None): 42
  :fun test_x
    @x ::t_type=> (U64 | None)
```

---

It infers an integer literal through an if statement:

```savi
    x (U64 | String | None) = if True (
      42 ::t_type=> U64
    )
    x ::t_type=> (U64 | String | None)
```

---

It infers an integer literal within the else body of an if statement:

```savi
    u = U64[99]
    x = if True (
      u
    |
      0 ::t_type=> U64
    ) ::t_type=> U64
```

---

It infers an integer through a variable with no explicit type:

```savi
    x = 99 ::t_type=> U64
    U64[99] == x
```

---

It infers an integer through a variable with only a cap as its explicit type:

```savi
    x box = 99 ::t_type=> U64
    U64[99] == x
```

---

It complains when a literal couldn't be resolved to a single type:

```savi
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

```savi
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

```savi
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

```savi
    x = ["one", "two", "three"] ::t_type=> Array(String)
    x                           ::t_type=> Array(String)
```

---

It infers the element types of an array literal from an assignment:

```savi
    // TODO: allow syntax: Array(U64 | None)'val?
    x Array((U64 | None))'val = [
      1 ::t_type=> U64
      2 ::t_type=> U64
      3 ::t_type=> U64
    ] ::t_type=> Array((U64 | None))
    x ::t_type=> Array((U64 | None))
```

---

TODO: It complains when lifting the cap of an array with non-sendable elements:

```savi
    s String'ref = String.new
    array1 Array(String'ref)'val = [String.new_iso, String.new_iso] // okay
    // array2 Array(String'ref)'val = [s, s] // not okay
```

---

It infers an empty array literal from its antecedent:

TODO: type assertions in savi.spec.md files:
```savi
    x Array(U64) = [] ::t_type=> Array(U64)
    x                 ::t_type=> Array(U64)
    x << 99
```

---

It complains when an empty array literal has no antecedent:

```savi
    x = []
    x << 99
```
```error
The type of this empty array literal could not be inferred (it needs an explicit type):
    x = []
        ^~
```

---

TODO: It complains when trying to implicitly recover an array literal:

```savi
    x_ref String'ref = String.new
    array_ref ref = [x_ref] // okay
    array_box box = [x_ref] // okay
    // array_val val = [x_ref] // not okay
```

---

TODO: It infers prop setters to return the alias of the assigned value:

```savi
:class HasStringIso
  :var string_iso String'iso: String.new_iso
```
```savi
    wrapper_iso = HasStringIso.new
    returned_2 String'tag = wrapper_iso.string_iso = String.new_iso // okay
    // returned_3 String'iso = wrapper_iso.string_iso = String.new_iso // not okay
```
